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

    init(url: String, title: String, outputDir: String, category: String) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.outputDir = outputDir
        self.timestamp = Date()
        self.category = category
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
        guard !isDownloading else {
            print("[DownloadManager] Bloqueado: já está baixando")
            return
        }
        print("[DownloadManager] download() chamado para: \(url)")
        isDownloading = true
        progress = 0
        statusText = "Iniciando..."
        logLines = ["Preparando download de: \(url)"]

        Task { @MainActor in
            print("[DownloadManager] Task iniciada, chamando runDownload")
            await runDownload(
                url: url, quality: quality, format: format,
                audioOnly: audioOnly, category: category,
                customFilename: customFilename,
                subtitles: subtitles, subLangs: subLangs,
                cookieBrowser: cookieBrowser
            )
            print("[DownloadManager] runDownload terminou")
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

                // Check if download succeeded based on statusText
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
        isDownloading = true
        statusText = "Instalando dependências..."
        logLines = ["🚀 Instalação automática iniciada"]
        progress = 0

        Task {
            let binDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin")
            try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            
            // Step 1: Install yt-dlp
            appendLog("📦 [1/2] Instalando yt-dlp...")
            statusText = "Instalando yt-dlp..."
            progress = 25
            
            let ytdlpDest = binDir.appendingPathComponent("yt-dlp")
            guard let ytdlpSrc = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos") else {
                statusText = "❌ URL inválida"; isDownloading = false; return
            }

            do {
                let (tmp, _) = try await URLSession.shared.download(from: ytdlpSrc)
                if FileManager.default.fileExists(atPath: ytdlpDest.path) {
                    try? FileManager.default.removeItem(at: ytdlpDest)
                }
                try FileManager.default.moveItem(at: tmp, to: ytdlpDest)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytdlpDest.path)
                appendLog("✅ yt-dlp instalado: \(ytdlpDest.path)")
                progress = 50
            } catch {
                statusText = "❌ Erro ao instalar yt-dlp"
                appendLog("Erro: \(error.localizedDescription)")
                isDownloading = false
                return
            }
            
            // Step 2: Install ffmpeg
            appendLog("")
            appendLog("📦 [2/2] Instalando ffmpeg...")
            statusText = "Instalando ffmpeg..."
            progress = 60
            
            let success = await installFfmpeg(to: binDir)
            
            if success {
                progress = 100
                statusText = "✅ Tudo instalado!"
                appendLog("")
                appendLog("━━━━━━━━━━━━━━━━━━━━━━━━")
                appendLog("✅ yt-dlp: \(ytdlpDest.path)")
                appendLog("✅ ffmpeg: \(binDir.appendingPathComponent("ffmpeg").path)")
                appendLog("━━━━━━━━━━━━━━━━━━━━━━━━")
                appendLog("")
                appendLog("🎉 Pronto! Agora você pode baixar vídeos!")
                
                try? await Task.sleep(for: .seconds(3))
                isDownloading = false
                progress = 0
            } else {
                statusText = "⚠️ yt-dlp OK, ffmpeg falhou"
                appendLog("")
                appendLog("⚠️ ffmpeg não foi instalado automaticamente")
                appendLog("Para melhor qualidade, instale manualmente:")
                appendLog("brew install ffmpeg")
                appendLog("")
                appendLog("Você ainda pode baixar vídeos, mas em formato único.")
                isDownloading = false
            }
        }
    }
    
    private func installFfmpeg(to binDir: URL) async -> Bool {
        // Detect architecture
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        
        let isAppleSilicon = machine?.contains("arm64") ?? false
        
        // ffmpeg binary URLs (from official static builds)
        let ffmpegURL: URL?
        
        if isAppleSilicon {
            appendLog("🔍 Detectado: Apple Silicon (M1/M2/M3)")
            ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip")
        } else {
            appendLog("🔍 Detectado: Intel Mac")
            ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip")
        }
        
        guard let url = ffmpegURL else {
            appendLog("❌ Não foi possível determinar URL do ffmpeg")
            return false
        }
        
        let ffmpegDest = binDir.appendingPathComponent("ffmpeg")
        let zipDest = binDir.appendingPathComponent("ffmpeg.zip")
        
        do {
            appendLog("⬇️ Baixando ffmpeg...")
            let (tmpZip, _) = try await URLSession.shared.download(from: url)
            
            // Move zip to bin dir
            if FileManager.default.fileExists(atPath: zipDest.path) {
                try? FileManager.default.removeItem(at: zipDest)
            }
            try FileManager.default.moveItem(at: tmpZip, to: zipDest)
            appendLog("✅ Download completo")
            
            // Unzip using system unzip command
            appendLog("📦 Extraindo ffmpeg...")
            let unzipProc = Process()
            unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProc.arguments = ["-o", zipDest.path, "-d", binDir.path]
            unzipProc.standardOutput = Pipe()
            unzipProc.standardError = Pipe()
            
            try unzipProc.run()
            unzipProc.waitUntilExit()
            
            // Make executable
            if FileManager.default.fileExists(atPath: ffmpegDest.path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegDest.path)
                appendLog("✅ ffmpeg instalado e pronto para uso")
                
                // Clean up zip
                try? FileManager.default.removeItem(at: zipDest)
                
                return true
            } else {
                appendLog("⚠️ ffmpeg não encontrado após extração")
                return false
            }
        } catch {
            appendLog("❌ Erro ao instalar ffmpeg: \(error.localizedDescription)")
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
        print("[DownloadManager] runDownload ENTROU")
        let ytdlpPath = VideoInfoService.shared.findYtdlp()
        print("[DownloadManager] findYtdlp returned: \(ytdlpPath ?? "nil")")
        
        guard let ytdlp = ytdlpPath else {
            statusText = "❌ yt-dlp não encontrado"
            appendLog("yt-dlp não encontrado. Instale com: brew install yt-dlp")
            return
        }

        appendLog("yt-dlp: \(ytdlp)")

        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/YTool")
        let platform = detectPlatform(url)
        let outputDir = baseDir.appendingPathComponent("\(platform)/\(category)")
        
        print("[DownloadManager] Criando pasta: \(outputDir.path)")
        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            print("[DownloadManager] Erro ao criar pasta: \(error)")
        }

        let name = customFilename.isEmpty ? "%(title)s" : sanitizeFilename(customFilename)
        let outputTemplate = outputDir.appendingPathComponent("\(name).%(ext)s").path

        var args = [
            "--newline",
            "--no-playlist",
            "--remote-components", "ejs:github",
            "-o", outputTemplate,
            "--user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "--add-header", "Accept:text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "--add-header", "Accept-Language:en-us,en;q=0.5",
            "--extractor-retries", "5",
            "--no-update"
        ]

        // Check if ffmpeg is available
        let hasFfmpeg = FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg") ||
                       FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg")
        
        if audioOnly {
            args += ["-x", "--audio-format", "mp3"]
        } else if hasFfmpeg {
            // ffmpeg available - can merge video+audio
            if quality != "best" {
                let h = quality.replacingOccurrences(of: "p", with: "")
                args += ["-f", "bestvideo[height<=\(h)]+bestaudio/best[height<=\(h)]",
                         "--merge-output-format", format]
            } else {
                args += ["-f", "bestvideo+bestaudio/best", "--merge-output-format", format]
            }
        } else {
            // No ffmpeg - download single format (already merged)
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

        // Auto cookies from browser (member content support)
        if let browser = cookieBrowser, !browser.isEmpty {
            args += ["--cookies-from-browser", browser]
            appendLog("Usando cookies do \(browser)")
        }

        args.append(url)
        print("[DownloadManager] Template: \(outputTemplate)")
        print("[DownloadManager] Args: \(args)")
        appendLog("Comando: yt-dlp \(args.joined(separator: " "))")
        statusText = "Baixando..."

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = args
        // Herda PATH com binários bundled (ffmpeg) + sistema
        var env = ProcessInfo.processInfo.environment
        let bundledBin = VideoInfoService.shared.bundledBinDir() ?? ""
        let extraPaths = [bundledBin, "/usr/local/bin", "/opt/homebrew/bin", NSHomeDirectory() + "/bin"]
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        env["PATH"] = extraPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.process = proc

        print("[DownloadManager] Tentando proc.run()...")
        do {
            try proc.run()
            print("[DownloadManager] proc.run() OK, pid=\(proc.processIdentifier)")
        } catch {
            print("[DownloadManager] proc.run() FALHOU: \(error)")
            statusText = "❌ Erro ao executar yt-dlp"
            appendLog(error.localizedDescription)
            return
        }

        // Stream output line-by-line in real time
        print("[DownloadManager] Streaming output em tempo real...")
        let fileHandle = pipe.fileHandleForReading

        let mgr = self
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task.detached {
                var buffer = Data()
                while true {
                    let chunk = fileHandle.availableData
                    if chunk.isEmpty { break } // EOF = process finished
                    buffer.append(chunk)

                    // Split on newlines and parse each line
                    while let range = buffer.range(of: Data([0x0A])) {
                        let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                        buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                        if let line = String(data: lineData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
                            print("[yt-dlp] \(line)")
                            await mgr.parseLine(line)
                        }
                    }
                }
                // Process remaining buffer
                if let rest = String(data: buffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !rest.isEmpty {
                    print("[yt-dlp] \(rest)")
                    await mgr.parseLine(rest)
                }
                continuation.resume()
            }
        }

        let exitCode = proc.terminationStatus
        print("[DownloadManager] Processo terminou. Exit: \(exitCode)")

        if exitCode == 0 {
            progress = 100
            statusText = "✅ Concluído!"
            let title = videoInfo?.title ?? ""
            let item = DownloadHistoryItem(
                url: url, title: title,
                outputDir: outputDir.path, category: category
            )
            history.insert(item, at: 0)
            if history.count > 100 { history = Array(history.prefix(100)) }
            saveHistory()
        } else if statusText != "Cancelado" {
            statusText = "❌ Erro (código \(exitCode))"
        }
    }

    // MARK: - Helpers

    private func parseLine(_ line: String) {
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

