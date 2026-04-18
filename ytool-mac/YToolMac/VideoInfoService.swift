import Foundation

struct VideoInfo: Equatable {
    let title: String
    let uploader: String
    let duration: Int
    let thumbnail: String
    let formats: [VideoFormat]

    var durationFormatted: String {
        guard duration > 0 else { return "" }
        let h = duration / 3600
        let m = (duration % 3600) / 60
        let s = duration % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

struct VideoFormat: Identifiable, Equatable {
    let id: String
    let label: String
    let kind: FormatKind
    let height: Int

    enum FormatKind: String, Equatable {
        case videoAudio = "video+audio"
        case videoOnly  = "video"
        case audioOnly  = "audio"

        var emoji: String {
            switch self {
            case .videoAudio: return "🎬"
            case .videoOnly:  return "📹"
            case .audioOnly:  return "🎵"
            }
        }
    }
}

enum VideoInfoError: LocalizedError {
    case ytdlpNotFound
    case fetchFailed(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .ytdlpNotFound:      return "yt-dlp não encontrado. Instale com: brew install yt-dlp"
        case .fetchFailed(let m): return "Falha: \(m)"
        case .parseError(let m):  return "Erro ao processar: \(m)"
        }
    }
}

final class VideoInfoService: Sendable {
    static let shared = VideoInfoService()

    // Procura yt-dlp: primeiro no bundle do app, depois no sistema
    private var searchPaths: [String] {
        var paths: [String] = []
        // 1. Bundled com o app (YToolMac_YToolMac.bundle/bin/)
        if let bundleURL = Bundle.main.resourceURL {
            // Swift Package resources ficam em YToolMac_YToolMac.bundle
            let bundledPath = bundleURL
                .appendingPathComponent("YToolMac_YToolMac.bundle")
                .appendingPathComponent("bin")
                .appendingPathComponent("yt-dlp")
            paths.append(bundledPath.path)
            // Também tenta direto no bundle
            let directPath = bundleURL
                .appendingPathComponent("bin")
                .appendingPathComponent("yt-dlp")
            paths.append(directPath.path)
        }
        // 2. Tenta via Bundle.module (Swift Package)
        if let moduleBundle = Bundle(identifier: "YToolMac.YToolMac") ?? Bundle.allBundles.first(where: { $0.bundlePath.contains("YToolMac_YToolMac") }) {
            let modulePath = moduleBundle.bundleURL
                .appendingPathComponent("bin")
                .appendingPathComponent("yt-dlp")
            paths.append(modulePath.path)
        }
        // 3. Sistema
        paths.append(contentsOf: [
            NSHomeDirectory() + "/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/opt/homebrew/bin/yt-dlp",
        ])
        return paths
    }

    /// Retorna o diretório dos binários bundled (ffmpeg, etc)
    func bundledBinDir() -> String? {
        if let bundleURL = Bundle.main.resourceURL {
            let path1 = bundleURL
                .appendingPathComponent("YToolMac_YToolMac.bundle")
                .appendingPathComponent("bin")
            if FileManager.default.fileExists(atPath: path1.path) { return path1.path }
            let path2 = bundleURL.appendingPathComponent("bin")
            if FileManager.default.fileExists(atPath: path2.path) { return path2.path }
        }
        if let moduleBundle = Bundle(identifier: "YToolMac.YToolMac") ?? Bundle.allBundles.first(where: { $0.bundlePath.contains("YToolMac_YToolMac") }) {
            let path = moduleBundle.bundleURL.appendingPathComponent("bin")
            if FileManager.default.fileExists(atPath: path.path) { return path.path }
        }
        return nil
    }

    func findYtdlp() -> String? {
        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                print("[VideoInfoService] Found yt-dlp at: \(path)")
                return path
            } else {
                let exists = FileManager.default.fileExists(atPath: path)
                if exists {
                    print("[VideoInfoService] Found but not executable: \(path)")
                } 
            }
        }
        print("[VideoInfoService] Searched paths: \(searchPaths)")
        // Fallback: try `which`
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["yt-dlp"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !output.isEmpty && FileManager.default.isExecutableFile(atPath: output) {
                return output
            }
        } catch {}
        return nil
    }

    func fetch(url: String, cookieBrowser: String? = nil) async throws -> VideoInfo {
        guard let ytdlp = findYtdlp() else {
            throw VideoInfoError.ytdlpNotFound
        }

        print("[VideoInfoService] Using yt-dlp at: \(ytdlp)")
        print("[VideoInfoService] Fetching info for: \(url)")

        var arguments = ["--no-playlist", "--remote-components", "ejs:github"]
        if let browser = cookieBrowser, !browser.isEmpty {
            arguments += ["--cookies-from-browser", browser]
            print("[VideoInfoService] Using cookies from: \(browser)")
        }
        arguments += ["-J", url]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(NSHomeDirectory())/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
            print("[VideoInfoService] pid=\(proc.processIdentifier)")
        } catch {
            throw VideoInfoError.fetchFailed(error.localizedDescription)
        }

        // Run waitUntilExit on a background DispatchQueue — never on main thread
        let (outData, exitCode): (Data, Int32) = try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                proc.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: (data, proc.terminationStatus))
            }
        }

        print("[VideoInfoService] Exit: \(exitCode), bytes: \(outData.count)")

        if exitCode != 0 {
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw VideoInfoError.fetchFailed(String(errStr.prefix(300)))
        }

        guard let json = try? JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            throw VideoInfoError.parseError("Resposta inválida")
        }

        let info = Self.parseInfo(json)
        print("[VideoInfoService] OK: \(info.title) — \(info.formats.count) formatos")
        return info
    }

    private static func parseInfo(_ json: [String: Any]) -> VideoInfo {
        let title     = json["title"]     as? String ?? ""
        let uploader  = json["uploader"]  as? String ?? json["channel"] as? String ?? ""
        let duration  = json["duration"]  as? Int ?? Int(json["duration"] as? Double ?? 0)
        let thumbnail = json["thumbnail"] as? String ?? ""

        var formats: [VideoFormat] = []
        for f in (json["formats"] as? [[String: Any]] ?? []) {
            let vcodec = f["vcodec"] as? String ?? "none"
            let acodec = f["acodec"] as? String ?? "none"
            let height = f["height"] as? Int ?? 0
            let ext    = f["ext"]    as? String ?? ""
            let fid    = f["format_id"] as? String ?? ""
            let tbr    = f["tbr"]    as? Double
            let fps    = f["fps"]    as? Double
            let filesize = (f["filesize"] as? Int) ?? (f["filesize_approx"] as? Int)

            let sizeStr = filesize.map { " ~\($0 / 1_048_576)MB" } ?? ""

            let kind: VideoFormat.FormatKind
            let label: String

            if vcodec == "none" && acodec != "none" {
                kind = .audioOnly
                let bitrate = tbr.map { "\(Int($0))kbps" } ?? ""
                label = "\(friendlyAcodec(acodec)) \(bitrate) .\(ext)\(sizeStr)".trimmingCharacters(in: .whitespaces)
            } else if vcodec != "none" {
                kind = acodec != "none" ? .videoAudio : .videoOnly
                let res = resLabel(height) ?? ext.uppercased()
                let fpsStr = (fps ?? 0) > 30 ? " \(Int(fps!))fps" : ""
                label = "\(res)\(fpsStr)  \(friendlyVcodec(vcodec)) .\(ext)\(sizeStr)"
            } else {
                continue
            }

            formats.append(VideoFormat(id: fid, label: label, kind: kind, height: height))
        }

        formats.sort {
            if $0.kind == .audioOnly && $1.kind != .audioOnly { return false }
            if $0.kind != .audioOnly && $1.kind == .audioOnly { return true }
            if $0.height != $1.height { return $0.height > $1.height }
            return false
        }

        return VideoInfo(title: title, uploader: uploader, duration: duration, thumbnail: thumbnail, formats: formats)
    }

    private static func resLabel(_ h: Int) -> String? {
        [2160: "4K", 1440: "2K", 1080: "1080p", 720: "720p",
         480: "480p", 360: "360p", 240: "240p", 144: "144p"][h]
    }

    private static func friendlyVcodec(_ c: String) -> String {
        let l = c.lowercased()
        if l.hasPrefix("avc") || l.hasPrefix("h264") { return "H.264" }
        if l.hasPrefix("hvc") || l.hasPrefix("h265") { return "H.265" }
        if l.hasPrefix("av0") || l.hasPrefix("av1")  { return "AV1" }
        if l.hasPrefix("vp9") { return "VP9" }
        return c.components(separatedBy: ".").first?.uppercased() ?? c
    }

    private static func friendlyAcodec(_ c: String) -> String {
        let l = c.lowercased()
        if l.hasPrefix("mp4a")  { return "AAC" }
        if l.hasPrefix("opus")  { return "Opus" }
        if l.hasPrefix("mp3")   { return "MP3" }
        if l.hasPrefix("vorbis"){ return "Vorbis" }
        return c.components(separatedBy: ".").first?.uppercased() ?? c
    }
}

// MARK: - Thread-safe one-shot continuation resumer

private final class OnceResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }
}
