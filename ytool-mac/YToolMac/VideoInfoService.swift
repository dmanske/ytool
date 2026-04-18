import Foundation

struct VideoInfo: Equatable {
    let title: String
    let uploader: String
    let duration: Int        // seconds
    let thumbnail: String    // URL string
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
    case parseError

    var errorDescription: String? {
        switch self {
        case .ytdlpNotFound:    return "yt-dlp não encontrado"
        case .fetchFailed(let m): return "Falha ao buscar: \(m)"
        case .parseError:       return "Erro ao processar resposta"
        }
    }
}

actor VideoInfoService {
    static let shared = VideoInfoService()

    private let ytdlpPaths = [
        Bundle.main.path(forResource: "yt-dlp", ofType: nil),
        NSHomeDirectory() + "/bin/yt-dlp",
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
        "/usr/bin/yt-dlp",
    ]

    func findYtdlp() -> String? {
        ytdlpPaths.compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    func fetch(url: String) async throws -> VideoInfo {
        guard let ytdlp = findYtdlp() else { throw VideoInfoError.ytdlpNotFound }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = ["--no-playlist", "-J", url]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        try proc.run()
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VideoInfoError.parseError
        }

        return parseInfo(json)
    }

    private func parseInfo(_ json: [String: Any]) -> VideoInfo {
        let title    = json["title"]    as? String ?? ""
        let uploader = json["uploader"] as? String ?? json["channel"] as? String ?? ""
        let duration = json["duration"] as? Int ?? 0
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

        // Sort: best quality first, audio last
        formats.sort {
            if $0.kind == .audioOnly && $1.kind != .audioOnly { return false }
            if $0.kind != .audioOnly && $1.kind == .audioOnly { return true }
            if $0.height != $1.height { return $0.height > $1.height }
            let order: [VideoFormat.FormatKind] = [.videoAudio, .videoOnly, .audioOnly]
            return (order.firstIndex(of: $0.kind) ?? 9) < (order.firstIndex(of: $1.kind) ?? 9)
        }

        return VideoInfo(title: title, uploader: uploader, duration: duration, thumbnail: thumbnail, formats: formats)
    }

    private func resLabel(_ h: Int) -> String? {
        [2160: "4K", 1440: "2K", 1080: "1080p", 720: "720p",
         480: "480p", 360: "360p", 240: "240p", 144: "144p"][h]
    }

    private func friendlyVcodec(_ c: String) -> String {
        let l = c.lowercased()
        if l.hasPrefix("avc") || l.hasPrefix("h264") { return "H.264" }
        if l.hasPrefix("hvc") || l.hasPrefix("h265") { return "H.265" }
        if l.hasPrefix("av0") || l.hasPrefix("av1")  { return "AV1" }
        if l.hasPrefix("vp9") { return "VP9" }
        if l.hasPrefix("vp8") { return "VP8" }
        return c.components(separatedBy: ".").first?.uppercased() ?? c
    }

    private func friendlyAcodec(_ c: String) -> String {
        let l = c.lowercased()
        if l.hasPrefix("mp4a")  { return "AAC" }
        if l.hasPrefix("opus")  { return "Opus" }
        if l.hasPrefix("mp3")   { return "MP3" }
        if l.hasPrefix("vorbis"){ return "Vorbis" }
        return c.components(separatedBy: ".").first?.uppercased() ?? c
    }
}
