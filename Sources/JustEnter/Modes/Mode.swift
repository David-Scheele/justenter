import Foundation

/// A mode bundles everything about how a dictation is transcribed, enhanced and delivered —
/// the same concept as Superwhisper's modes.
struct Mode: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String = "waveform"
    var details: String = ""
    /// The Auto mode picks one of the other modes per dictation (by app, then content).
    var isAuto: Bool = false

    /// When false the raw transcript is used verbatim (no AI pass).
    var aiEnabled: Bool = true
    /// The instruction the AI receives as its system prompt for this mode.
    var prompt: String = ""

    /// Bundle identifiers that auto-activate this mode when the app comes to front.
    var activationBundleIDs: [String] = []

    /// BCP-47 language code, empty = automatic / global setting.
    var language: String = ""

    /// Context sent along to Claude.
    var includeSelectedText: Bool = false
    var includeClipboard: Bool = false
    var includeActiveApp: Bool = true

    /// Inject the user vocabulary + knowledge base into the prompt.
    var useVocabulary: Bool = true
    var useKnowledgeBase: Bool = false

    /// Delivery
    var restoreClipboard: Bool = true

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, details, isAuto, aiEnabled, prompt, activationBundleIDs,
             language, includeSelectedText, includeClipboard, includeActiveApp,
             useVocabulary, useKnowledgeBase, restoreClipboard
    }

    static func autoMode() -> Mode {
        Mode(
            name: "Auto",
            symbol: "wand.and.stars",
            details: "Detects the best mode for each dictation — by the app you're in, then by what you said.",
            isAuto: true,
            aiEnabled: true,
            includeSelectedText: true,
            includeActiveApp: true,
            useVocabulary: true,
            useKnowledgeBase: true
        )
    }

    static func defaults() -> [Mode] {
        [
            Mode(
                name: "Transcription",
                symbol: "text.quote",
                details: "Accurate verbatim transcription, lightly cleaned up.",
                aiEnabled: false,
                prompt: ""
            ),
            Mode(
                name: "Message",
                symbol: "bubble.left.and.bubble.right",
                details: "Casual tone for chats — Slack, iMessage, WhatsApp.",
                aiEnabled: true,
                prompt: """
                You clean up dictated chat messages. Fix grammar, remove filler words \
                (um, uh, like, you know), stutters and false starts. Keep the casual, \
                friendly tone of a chat message. Keep it concise. Do not add greetings \
                or sign-offs that the speaker didn't say. Preserve the speaker's language \
                (if they dictate in German, answer in German). Output only the cleaned \
                message, nothing else.
                """,
                activationBundleIDs: ["com.tinyspeck.slackmacgap", "com.apple.MobileSMS"],
                includeActiveApp: true
            ),
            Mode(
                name: "Email",
                symbol: "envelope",
                details: "Well-structured, professional email prose.",
                aiEnabled: true,
                prompt: """
                You turn dictation into polished email text. Fix grammar and remove filler \
                words, organize the content into clear paragraphs, and keep a professional \
                but warm tone. Preserve the speaker's intent and language. If the dictation \
                contains a greeting or sign-off keep it; never invent one. Output only the \
                email text, nothing else.
                """,
                activationBundleIDs: ["com.apple.mail", "com.microsoft.Outlook"],
                includeSelectedText: true
            ),
            Mode(
                name: "Notes",
                symbol: "note.text",
                details: "Structured notes with headings and bullet points.",
                aiEnabled: true,
                prompt: """
                You turn spoken thoughts into clean, structured notes. Use markdown: short \
                headings where topics change, bullet points for lists, bold for key terms. \
                Remove filler words and repetitions but keep every piece of information. \
                Preserve the speaker's language. Output only the notes, nothing else.
                """,
                activationBundleIDs: ["com.apple.Notes", "md.obsidian"]
            ),
            Mode(
                name: "Prompt",
                symbol: "terminal",
                details: "Precise prompts for AI tools and coding assistants.",
                aiEnabled: true,
                prompt: """
                You clean up dictated prompts for AI assistants and coding tools. Fix \
                grammar and remove filler, but keep all technical terms, file names, code \
                identifiers and constraints exactly as spoken. Keep the imperative, direct \
                style. Do not answer the prompt — only clean it up. Output only the cleaned \
                prompt, nothing else.
                """,
                activationBundleIDs: ["com.microsoft.VSCode", "com.apple.Terminal", "com.googlecode.iterm2"],
                useVocabulary: true
            ),
        ]
    }
}

extension Mode {
    /// Resilient decoding: missing keys fall back to defaults so saved modes
    /// survive schema changes instead of being replaced wholesale.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Mode"
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol) ?? "waveform"
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        isAuto = try container.decodeIfPresent(Bool.self, forKey: .isAuto) ?? false
        aiEnabled = try container.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? true
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        activationBundleIDs = try container.decodeIfPresent([String].self, forKey: .activationBundleIDs) ?? []
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        includeSelectedText = try container.decodeIfPresent(Bool.self, forKey: .includeSelectedText) ?? false
        includeClipboard = try container.decodeIfPresent(Bool.self, forKey: .includeClipboard) ?? false
        includeActiveApp = try container.decodeIfPresent(Bool.self, forKey: .includeActiveApp) ?? true
        useVocabulary = try container.decodeIfPresent(Bool.self, forKey: .useVocabulary) ?? true
        useKnowledgeBase = try container.decodeIfPresent(Bool.self, forKey: .useKnowledgeBase) ?? false
        restoreClipboard = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? true
    }
}
