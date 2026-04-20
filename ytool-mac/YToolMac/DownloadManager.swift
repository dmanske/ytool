import Foundation
import SwiftUI

// MARK: - Models

struct DownloadHistoryItem: Identifiable, Codable {
    let id: UUID
    let url: String
    let title: String
    let outputDir: String
    let timestamp: Date
    let category: String
    let thumbnailURL: String

    init(url: String, title: String, outputDir: String, category: String, thumbnailURL: String = "") {
        self.id = UUID()
        self.url = url
        self.title = title
        self.outputDir = outputDir
        self.timestamp = Date()
        self.category = category
        self.thumbnailURL = thumbnailURL
    }
}

struct QueueItem: Identifiable {
    let id = UUID()
    let url: String
    let quality: String
    let format: String
    let audioOnly: Bool
    let category: String
    let customFilename: String
    let subtitles: Bool
    let subLangs: String
    var status: QueueStatus = .pending

    enum QueueStatus { case pending, active, done, error }
}

// MARK: - DownloadManager

@MainActor
final class DownloadManager: ObservableObject {

    // Current download state
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var logLines: [String] = []

    // Installation state
    @Published var isInstalling = false
    @Published var dependenciesReady = false
    @Published var ytdlpVersion: String? = nil   // nil = not checked yet, "" = not found

    // Last completed download (for preview card)
    @Published var lastDownload: DownloadHistoryItem? = nil

    // Metadata parsed live from yt-dlp output
    private var parsedTitle = ""
    private var parsedThumbnail = ""

    // Queue
    @Published var queue: [QueueItem] = []
    @Published var isProcessingQueue = false

    // History
    @Published var history: [DownloadHistoryItem] = []

    // Video info from inspection
    @Published var videoInfo: VideoInfo?

    private var process: Process?
    private let historyURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ytool")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        loadHistory()
        checkAndAutoInstall()
        checkYtdlpVersion()
    }

    // MARK: - Version check (shows actual installed version)

    func checkYtdlpVersion() {
        Task {
            guard let ytdlp = VideoInfoService.shared.findYtdlp() else {
                ytdlpVersion = ""
                return
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ytdlp)
            proc.arguments = ["--version"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run(); proc.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                ytdlpVersion = out.isEmpty ? "" : out
            } catch {
                ytdlpVersion = ""
            }
        }
    }

    // MARK: - Auto-install on first launch

    private func checkAndAutoInstall() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let homeYtdlp = home.appendingPathComponent("bin/yt-dlp").path
        let brewPaths = ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/yt-dlp"]

        // Só marca como pronto se tiver versão NÃO-bundled (fresca)
        let hasFreshYtdlp = FileManager.default.isExecutableFile(atPath: homeYtdlp)
            || brewPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }

        if hasFreshYtdlp {
            dependenciesReady = true
        } else {
            // Bundle antigo ou nada → baixar versão nova automaticamente
            installYtdlp()
        }
    }

    // MARK: - Single download

    func download(
        url: String,
        quality: String,
        format: String,
        audioOnly: Bool,
        category: String,
        customFilename: String = "",
        subtitles: Bool = false,
        subLangs: String = "en,pt",
        cookieBrowser: String? = nil
    ) {
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0
        statusText = "Iniciando..."
        logLines = ["Preparando download de: \(url)"]

        Task { @MainActor in
            await runDownload(
                url: url, quality: quality, format: format,
                audioOnly: audioOnly, category: category,
                customFilename: customFilename,
                subtitles: subtitles, subLangs: subLangs,
                cookieBrowser: cookieBrowser
            )
            isDownloading = false
        }
    }

    // MARK: - Queue

    func addToQueue(
        url: String, quality: String, format: String,
        audioOnly: Bool, category: String,
        customFilename: String = "",
        subtitles: Bool = false, subLangs: String = "en,pt"
    ) {
        queue.append(QueueItem(
            url: url, quality: quality, format: format,
            audioOnly: audioOnly, category: category,
            customFilename: customFilename,
            subtitles: subtitles, subLangs: subLangs
        ))
    }

    func removeFromQueue(id: UUID) {
        queue.removeAll { $0.id == id }
    }

    func startQueue() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        Task {
            for i in queue.indices where queue[i].status == .pending {
                queue[i].status = .active
                progress = 0
                statusText = "Iniciando..."
                logLines = []
                isDownloading = true

                let item = queue[i]
                await runDownload(
                    url: item.url, quality: item.quality, format: item.format,
                    audioOnly: item.audioOnly, category: item.category,
                    customFilename: item.customFilename,
                    subtitles: item.subtitles, subLangs: item.subLangs
                )

                queue[i].status = statusText.contains("✅") ? .done : .error
                isDownloading = false
            }
            isProcessingQueue = false
            queue.removeAll { $0.status == .done }
        }
    }

    // MARK: - Cancel

    func cancel() {
        process?.terminate()
        isDownloading = false
        statusText = "Cancelado"
    }

    // MARK: - Install Dependencies (yt-dlp + ffmpeg)

    func installYtdlp() {
        guard !isInstalling else { return }
        isInstalling = true
        isDownloading = true
        statusText = "Instalando dependências..."
        logLines = ["🚀 Configuração inicial — isso só acontece uma vez"]
        progress = 0

        Task {
            let binDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin")
            try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

            // Step 1: Install yt-dlp
            appendLog("📦 [1/2] Baixando yt-dlp...")
            statusText = "Baixando yt-dlp..."
            progress = 20

            let ytdlpDest = binDir.appendingPathComponent("yt-dlp")
            guard let ytdlpSrc = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos") else {
                statusText = "❌ URL inválida"; isInstalling = false; isDownloading = false; return
            }

            do {
                let (tmp, _) = try await URLSession.shared.download(from: ytdlpSrc)
                if FileManager.default.fileExists(atPath: ytdlpDest.path) {
                    try? FileManager.default.removeItem(at: ytdlpDest)
                }
                try FileManager.default.moveItem(at: tmp, to: ytdlpDest)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytdlpDest.path)
                appendLog("✅ yt-dlp instalado")
                progress = 50
            } catch {
                statusText = "❌ Erro ao instalar yt-dlp"
                appendLog("Erro: \(error.localizedDescription)")
                isInstalling = false
                isDownloading = false
                return
            }

            // Step 2: Install ffmpeg
            appendLog("📦 [2/2] Baixando ffmpeg...")
            statusText = "Baixando ffmpeg..."
            progress = 60

            let ffmpegOk = await installFfmpeg(to: binDir)

            progress = 100
            if ffmpegOk {
                statusText = "✅ Pronto para usar!"
                appendLog("✅ ffmpeg instalado")
                appendLog("🎉 Tudo configurado! Cole um link e clique em Baixar.")
            } else {
                statusText = "⚠️ yt-dlp OK · ffmpeg opcional"
                appendLog("⚠️ ffmpeg não instalado — vídeos serão baixados em formato único")
                appendLog("Para melhor qualidade: brew install ffmpeg")
            }

            dependenciesReady = true
            isInstalling = false
            checkYtdlpVersion()
            try? await Task.sleep(for: .seconds(2))
            isDownloading = false
            progress = 0
            statusText = ""
        }
    }

    private func installFfmpeg(to binDir: URL) async -> Bool {
        guard let url = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip") else { return false }

        let ffmpegDest = binDir.appendingPathComponent("ffmpeg")
        let zipDest = binDir.appendingPathComponent("ffmpeg.zip")

        do {
            let (tmpZip, _) = try await URLSession.shared.download(from: url)
            if FileManager.default.fileExists(atPath: zipDest.path) {
                try? FileManager.default.removeItem(at: zipDest)
            }
            try FileManager.default.moveItem(at: tmpZip, to: zipDest)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipDest.path, "-d", binDir.path]
            unzip.standardOutput = Pipe(); unzip.standardError = Pipe()
            try unzip.run(); unzip.waitUntilExit()

            if FileManager.default.fileExists(atPath: ffmpegDest.path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegDest.path)
                try? FileManager.default.removeItem(at: zipDest)
                return true
            }
            return false
        } catch {
            appendLog("ffmpeg: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - History persistence

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let items = try? JSONDecoder().decode([DownloadHistoryItem].self, from: data)
        else { return }
        history = items
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyURL)
    }

    func clearHistory() {
        history.removeAll()
        try? FileManager.default.removeItem(at: historyURL)
    }

    // MARK: - Core download runner

    private func runDownload(
        url: String, quality: String, format: String,
        audioOnly: Bool, category: String,
        customFilename: String,
        subtitles: Bool, subLangs: String,
        cookieBrowser: String? = nil
    ) async {
        guard let ytdlp = VideoInfoService.shared.findYtdlp() else {
            statusText = "❌ yt-dlp não encontrado — clique em Instalar"
            appendLog("yt-dlp não encontrado. Clique em Instalar dependências.")
            return
        }

        appendLog("yt-dlp: \(ytdlp)")

        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/YTool")
        let platform = detectPlatform(url)
        let outputDir = baseDir.appendingPathComponent("\(platform)/\(category)")

        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            print("[DownloadManager] Erro ao criar pasta: \(error)")
        }

        let name = customFilename.isEmpty ? "%(title)s" : sanitizeFilename(customFilename)
        let outputTemplate = outputDir.appendingPathComponent("\(name).%(ext)s").path

        // Reset parsed metadata for this download
        parsedTitle = ""
        parsedThumbnail = ""

        var args = [
            "--newline",
            "--no-playlist",
            "--remote-components", "ejs:github",
            "--print", "YTOOL_TITLE:%(title)s",
            "--print", "YTOOL_THUMB:%(thumbnail)s",
            "-o", outputTemplate,
            "--user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "--add-header", "Accept:text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "--add-header", "Accept-Language:en-us,en;q=0.5",
            "--extractor-retries", "5",
            "--no-update"
        ]

        // Check ffmpeg availability (bundled or system)
        let bundledBin = VideoInfoService.shared.bundledBinDir() ?? ""
        let hasFfmpeg = FileManager.default.fileExists(atPath: bundledBin + "/ffmpeg") ||
                        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/bin/ffmpeg") ||
                        FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg") ||
                        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg")

        if audioOnly {
            args += ["-x", "--audio-format", "mp3"]
        } else if hasFfmpeg {
            if quality != "best" {
                let h = quality.replacingOccurrences(of: "p", with: "")
                args += ["-f", "bestvideo[height<=\(h)]+bestaudio/best[height<=\(h)]",
                         "--merge-output-format", format]
            } else {
                args += ["-f", "bestvideo+bestaudio/best", "--merge-output-format", format]
            }
        } else {
            appendLog("⚠️ ffmpeg não encontrado - baixando formato único")
            if quality != "best" {
                let h = quality.replacingOccurrences(of: "p", with: "")
                args += ["-f", "best[height<=\(h)]/best"]
            } else {
                args += ["-f", "best"]
            }
        }

        if subtitles {
            args += ["--write-subs", "--write-auto-subs",
                     "--sub-langs", subLangs,
                     "--convert-subs", "srt",
                     "--ignore-errors"]
        }

        if let browser = cookieBrowser, !browser.isEmpty {
            args += ["--cookies-from-browser", browser]
            appendLog("Usando cookies do \(browser)")
        }

        args.append(url)
        appendLog("Comando: yt-dlp \(args.joined(separator: " "))")
        statusText = "Baixando..."

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        let extraPaths = [bundledBin, NSHomeDirectory() + "/bin", "/usr/local/bin", "/opt/homebrew/bin"]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.process = proc

        do {
            try proc.run()
        } catch {
            statusText = "❌ Erro ao executar yt-dlp"
            appendLog(error.localizedDescription)
            return
        }

        let fileHandle = pipe.fileHandleForReading
        let mgr = self
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task.detached {
                var buffer = Data()
                while true {
                    let chunk = fileHandle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let range = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                        if let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                            await mgr.parseLine(line)
                        }
                    }
                }
                if let rest = String(data: buffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !rest.isEmpty {
                    await mgr.parseLine(rest)
                }
                continuation.resume()
            }
        }

        let exitCode = proc.terminationStatus
        if exitCode == 0 {
            progress = 100
            statusText = "✅ Concluído!"
            let title = parsedTitle.isEmpty ? (videoInfo?.title ?? "") : parsedTitle
            let thumb = parsedThumbnail.isEmpty ? (videoInfo?.thumbnail ?? "") : parsedThumbnail
            let item = DownloadHistoryItem(
                url: url, title: title,
                outputDir: outputDir.path, category: category,
                thumbnailURL: thumb
            )
            lastDownload = item
            history.insert(item, at: 0)
            if history.count > 100 { history = Array(history.prefix(100)) }
            saveHistory()
        } else if statusText != "Cancelado" {
            statusText = "❌ Erro (código \(exitCode))"
        }
    }

    // MARK: - Helpers

    private func parseLine(_ line: String) {
        // Capture metadata printed by --print flags
        if line.hasPrefix("YTOOL_TITLE:") {
            let val = String(line.dropFirst("YTOOL_TITLE:".count))
            if !val.isEmpty && val != "NA" { parsedTitle = val }
            return
        }
        if line.hasPrefix("YTOOL_THUMB:") {
            let val = String(line.dropFirst("YTOOL_THUMB:".count))
            if !val.isEmpty && val != "NA" && val.hasPrefix("http") { parsedThumbnail = val }
            return
        }

        // Progress line
        let pattern = #"\[download\]\s+([\d.]+)%\s+of\s+(\S+)\s+at\s+(Unknown B/s|Unknown|\S+)\s+ETA\s+(\S+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            let nsLine = line as NSString
            let pctStr = nsLine.substring(with: match.range(at: 1))
            let speed  = nsLine.substring(with: match.range(at: 3))
            let eta    = nsLine.substring(with: match.range(at: 4))
            if let pct = Double(pctStr) {
                progress = pct
                statusText = "Baixando · \(speed) · ETA \(eta)"
            }
        } else {
            appendLog(line)
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 100 { logLines.removeFirst() }
    }

    private func detectPlatform(_ url: String) -> String {
        if url.contains("youtube.com") || url.contains("youtu.be") { return "youtube" }
        if url.contains("instagram.com") { return "instagram" }
        return "other"
    }

    private func sanitizeFilename(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: #"\/:*?"<>|"#))
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
}
