import AppKit
import Combine
import Foundation

/// Checks GitHub Releases for new versions and installs them in place:
/// download zip → extract → swap /Applications/JustEnter.app → relaunch.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private let repo = "David-Scheele/justenter"
    private var downloadURL: URL?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var updateAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    var availableVersion: String? {
        if case .available(let version) = status { return version }
        return nil
    }

    private var token: String {
        AppSettings.shared.githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    func check() async {
        status = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.timeoutInterval = 15
        authorize(&request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard statusCode != 404, statusCode != 401, statusCode != 403 else {
                status = .failed(token.isEmpty
                    ? "GitHub returned \(statusCode) — try again later."
                    : "GitHub rejected the token — check its repo access.")
                return
            }
            guard statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String
            else {
                status = .failed("No release found.")
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let assets = json["assets"] as? [[String: Any]] ?? []
            let zipAsset = assets.first {
                ($0["name"] as? String) == "JustEnter.zip"
            }
            // The asset *API* URL works on private repos (browser_download_url doesn't).
            downloadURL = (zipAsset?["url"] as? String).flatMap(URL.init(string:))

            if Self.isNewer(latest, than: Self.currentVersion), downloadURL != nil {
                status = .available(version: latest)
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed("Update check failed: \(error.localizedDescription)")
        }
    }

    /// Downloads the release, swaps the installed app and relaunches.
    func installUpdate() async {
        guard case .available = status, let downloadURL else { return }
        status = .downloading
        do {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("JustEnterUpdate-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let zipURL = staging.appendingPathComponent("JustEnter.zip")

            var request = URLRequest(url: downloadURL)
            request.timeoutInterval = 300
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            // GitHub redirects asset downloads to storage that rejects the auth header.
            let (temporary, response) = try await URLSession.shared.download(
                for: request,
                delegate: AuthStrippingRedirectDelegate()
            )
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                status = .failed("Download failed.")
                return
            }
            try FileManager.default.moveItem(at: temporary, to: zipURL)

            status = .installing
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-xk", zipURL.path, staging.path]
            try unzip.run()
            unzip.waitUntilExit()
            let newApp = staging.appendingPathComponent("JustEnter.app")
            guard unzip.terminationStatus == 0,
                  FileManager.default.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/JustEnter").path)
            else {
                status = .failed("The downloaded update is damaged.")
                return
            }

            // Swap after this process exits, then relaunch.
            let script = """
            sleep 1
            rm -rf "/Applications/JustEnter.app"
            mv "\(newApp.path)" "/Applications/JustEnter.app"
            open "/Applications/JustEnter.app"
            """
            let swapper = Process()
            swapper.executableURL = URL(fileURLWithPath: "/bin/sh")
            swapper.arguments = ["-c", script]
            try swapper.run()
            NSApp.terminate(nil)
        } catch {
            status = .failed("Update failed: \(error.localizedDescription)")
        }
    }

    /// Drops the Authorization header when GitHub redirects to its asset storage,
    /// which rejects requests carrying both a signed URL and an auth header.
    private final class AuthStrippingRedirectDelegate: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            var stripped = request
            stripped.setValue(nil, forHTTPHeaderField: "Authorization")
            completionHandler(stripped)
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
