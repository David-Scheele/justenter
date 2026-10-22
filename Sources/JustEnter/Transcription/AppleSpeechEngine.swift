import AVFoundation
import NaturalLanguage
import Speech

/// On-device streaming transcription via the macOS 26 SpeechAnalyzer / SpeechTranscriber API.
/// With auto language detection, one transcriber per preferred language runs in parallel
/// on the same audio and the result that best matches its own language wins.
@MainActor
final class AppleSpeechEngine: TranscriptionEngine {
    let kind: SpeechEngineKind = .apple
    var onPartial: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    /// One transcriber candidate and what it heard.
    private final class Candidate {
        let locale: Locale
        let transcriber: SpeechTranscriber
        var finalText = ""

        init(locale: Locale, transcriber: SpeechTranscriber) {
            self.locale = locale
            self.transcriber = transcriber
        }
    }

    private var analyzer: SpeechAnalyzer?
    private var candidates: [Candidate] = []
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var recognizerTasks: [Task<Void, Never>] = []

    /// Single-flight asset install, re-run when the language selection changes.
    private var prepareTask: Task<Void, Error>?
    private var preparedKey = ""

    func prepare(request: TranscriptionRequest) async throws {
        let key = "\(request.autoDetect)|\(request.locale.identifier)"
        if key != preparedKey {
            prepareTask = nil
        }
        if prepareTask == nil {
            prepareTask = Task { [weak self] in
                do {
                    try await self?.installAssets(for: request)
                    self?.preparedKey = key
                } catch {
                    self?.prepareTask = nil // allow a retry after a failure
                    throw error
                }
            }
        }
        try await prepareTask!.value
    }

    private func installAssets(for request: TranscriptionRequest) async throws {
        let locales = try await resolveCandidateLocales(for: request)
        let probes = locales.map {
            SpeechTranscriber(locale: $0, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        }
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: probes) {
            let progress = downloader.progress
            let poll = Task { [weak self] in
                while !Task.isCancelled {
                    self?.onStatus?("Downloading \(Int(progress.fractionCompleted * 100))%")
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
            defer { poll.cancel() }
            try await downloader.downloadAndInstall()
        }
    }

    func startSession(request: TranscriptionRequest) async throws {
        converter = nil
        recognizerTasks = []

        let locales = try await resolveCandidateLocales(for: request)
        candidates = locales.map { locale in
            Candidate(
                locale: locale,
                transcriber: SpeechTranscriber(
                    locale: locale,
                    transcriptionOptions: [],
                    reportingOptions: [],
                    attributeOptions: []
                )
            )
        }

        let analyzer = SpeechAnalyzer(modules: candidates.map(\.transcriber))
        self.analyzer = analyzer

        if !request.vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = request.vocabulary
            try await analyzer.setContext(context)
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: candidates.map(\.transcriber)) else {
            throw engineError("Apple Speech has no compatible audio format for this language selection.")
        }
        analyzerFormat = format

        let (stream, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputBuilder = builder

        for candidate in candidates {
            let task = Task {
                do {
                    for try await result in candidate.transcriber.results where result.isFinal {
                        candidate.finalText += String(result.text.characters)
                    }
                } catch {
                    // Session ended or was cancelled; keep whatever accumulated.
                }
            }
            recognizerTasks.append(task)
        }

        try await analyzer.start(inputSequence: stream)
    }

    func feed(buffer: AVAudioPCMBuffer) {
        guard let inputBuilder, let analyzerFormat else { return }
        guard let converted = convert(buffer, to: analyzerFormat) else { return }
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }

    func finish(samples16k: [Float]) async throws -> String {
        inputBuilder?.finish()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        for task in recognizerTasks {
            _ = await task.value
        }
        let text = pickBestTranscript()
        cleanup()
        return text
    }

    func cancel() {
        inputBuilder?.finish()
        recognizerTasks.forEach { $0.cancel() }
        let analyzer = analyzer
        Task { await analyzer?.cancelAndFinishNow() }
        cleanup()
    }

    // MARK: - Language selection

    private func resolveCandidateLocales(for request: TranscriptionRequest) async throws -> [Locale] {
        guard request.autoDetect else {
            return [try await resolveLocale(request.locale)]
        }
        var result: [Locale] = []
        var seenLanguages = Set<String>()
        for identifier in Locale.preferredLanguages {
            guard result.count < 2 else { break }
            let preferred = Locale(identifier: identifier)
            guard let language = preferred.language.languageCode?.identifier,
                  !seenLanguages.contains(language),
                  let resolved = try? await resolveLocale(preferred)
            else { continue }
            seenLanguages.insert(language)
            result.append(resolved)
        }
        if result.isEmpty {
            result = [try await resolveLocale(request.locale)]
        }
        return result
    }

    /// Multiple candidates heard the same audio — the transcript that reads like its
    /// own transcriber's language is the one the user actually spoke.
    private func pickBestTranscript() -> String {
        let viable = candidates
            .map { (candidate: $0, text: $0.finalText.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
        guard viable.count > 1 else {
            return viable.first?.text ?? ""
        }

        func score(_ entry: (candidate: Candidate, text: String)) -> Double {
            guard let ownLanguage = entry.candidate.locale.language.languageCode?.identifier else { return 0 }
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(entry.text)
            var value = 0.0
            if let dominant = recognizer.dominantLanguage, dominant.rawValue.hasPrefix(ownLanguage) {
                value += 1.0
            }
            // Probability that this text really is the transcriber's own language.
            let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
            value += hypotheses.first(where: { $0.key.rawValue.hasPrefix(ownLanguage) })?.value ?? 0
            return value
        }

        return viable.max(by: { score($0) < score($1) })?.text ?? viable[0].text
    }

    // MARK: - Internals

    private func cleanup() {
        inputBuilder = nil
        recognizerTasks = []
        analyzer = nil
        candidates = []
        analyzerFormat = nil
        converter = nil
    }

    private func resolveLocale(_ requested: Locale) async throws -> Locale {
        if let equivalent = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return equivalent
        }
        let supported = await SpeechTranscriber.supportedLocales
        let language = requested.language.languageCode?.identifier ?? "en"
        if let match = supported.first(where: { $0.language.languageCode?.identifier == language }) {
            return match
        }
        throw engineError("Apple Speech doesn't support the language “\(requested.identifier)”.")
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard buffer.format != format else { return buffer }
        if converter == nil || converter?.outputFormat != format || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: max(capacity, 1)) else {
            return nil
        }
        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: out, error: &conversionError) { _, statusPointer in
            defer { consumed = true }
            statusPointer.pointee = consumed ? .noDataNow : .haveData
            return consumed ? nil : buffer
        }
        guard status != .error else { return nil }
        return out
    }

    private func engineError(_ message: String) -> NSError {
        NSError(domain: "JustEnter.AppleSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
