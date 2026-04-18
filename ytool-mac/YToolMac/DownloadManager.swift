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
        subLangs: String = "en,pt"
    ) {
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0
        statusText = "Iniciando..."
        logLines = []

        Task {
            await runDownload(
                url: url, quality: quality, format: format,
                audioOnly: audioOnly, category: category,
                customFilename: customFilename,
                subtitles: subtitles, subLangs: subLangs
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
                isDownloading = true
                progress = 0
                statusText = "Iniciando..."
                logLines = []

                let item = queue[i]
                await runDownload(
                    url: item.url, quality: item.quality, format: item.format,
                    audioOnly: item.audioOnly, category: item.category,
                    customFilename: item.customFilename,
                    subtitles: item.subtitles, subLangs: item.subLangs
                )

                queue[i].status = isDownloading ? .done : .error
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

    // MARK: - Install yt-dlp

    func installYtdlp() {
        isDownloading = true
        statusText = "Instalando yt-dlp..."
        logLines = ["Baixando de github.com/yt-dlp/yt-dlp..."]

        Task {
            let binDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("bin")
            try? FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
            let dest = binDir.appendingPathComponent("yt-dlp")

            guard let src = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos") else {
                statusText = "❌ URL inválida"; isDownloading = false; return
            }

            do {
                let (tmp, _) = try await URLSession.shared.download(from: src)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: tmp, to: dest)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
                statusText = "✅ yt-dlp instalado!"
                logLines.append("Instalado em: \(dest.path)")
                progress = 100
                try? await Task.sleep(for: .seconds(2))
                isDownloading = false
                progress = 0
            } catch {
                statusText = "❌ Erro ao instalar"
                logLines.append(error.localizedDescription)
                isDownloading = false
            }
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
        subtitles: Bool, subLangs: String
    ) async {
        guard let ytdlp = await VideoInfoService.shared.findYtdlp() else {
            statusText = "❌ yt-dlp não encontrado"
            appendLog("Instale com: brew install yt-dlp")
            return
        }

        let baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/YTool")
        let platform = detectPlatform(url: url)
        let outputDir = baseDir.appendingPathComponent("\(platform)/\(category)")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let name = customFilename.isEmpty ? "%(title)s" : sanitizeFilename(customFilename)
        let outputTemplate = outputDir.appendingPathComponent("\(name).%(ext)s").path

        var args = ["--newline", "--no-playlist", "-o", outputTemplate]

        if audioOnly {
            args += ["-x", "--audio-format", "mp3"]
        } else if quality != "best" {
            let h = quality.replacingOccurrences(of: "p", with: "")
            args += ["-f", "bestvideo[height<=\(h)]+bestaudio/best[height<=\(h)]",
                     "--merge-output-format", format]
        } else {
            args += ["-f", "bestvideo+bestaudio/best", "--merge-output-format", format]
        }

        if subtitles {
            args += ["--write-subs", "--write-auto-subs",
                     "--sub-langs", subLangs,
                     "--convert-subs", "srt",
                     "--ignore-errors"]
        }

        args.append(url)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = args

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.process = proc

        do {
            try proc.run()
            statusText = "Conectando..."
        } catch {
            statusText = "❌ Erro ao executar yt-dlp"
            appendLog(error.localizedDescription)
            return
        }

        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                parseLine(line)
            }
        } catch {
            appendLog("Erro ao ler saída: \(error.localizedDescription)")
        }

        proc.waitUntilExit()

        if proc.terminationStatus == 0 {
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
            statusText = "❌ Erro (código \(proc.terminationStatus))"
        }
    }

    // MARK: - Helpers

    private func parseLine(_ line: String) {
        let pattern = #"\[download\]\s+([\d.]+)%\s+of\s+(\S+)\s+at\s+(\S+)\s+ETA\s+(\S+)"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            let parts = String(line[range])
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            if let pct = Double(parts[safe: 1]?.replacingOccurrences(of: "%", with: "") ?? "") {
                progress = pct
                let speed = parts[safe: 5] ?? ""
                let eta   = parts[safe: 7] ?? ""
                statusText = "Baixando\(speed.isEmpty ? "" : " · \(speed)")\(eta.isEmpty ? "" : " · ETA \(eta)")"
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

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
