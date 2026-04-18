import Foundation
import SwiftUI

struct DownloadHistoryItem: Identifiable {
    let id = UUID()
    let url: String
    let title: String
    let outputDir: String
    let timestamp: Date
    let category: String
}

@MainActor
class DownloadManager: ObservableObject {
    @Published var isDownloading = false
    @Published var progress: Double = 0
    @Published var statusText = ""
    @Published var logLines: [String] = []
    @Published var history: [DownloadHistoryItem] = []
    @Published var videoInfo: VideoInfo?

    private var process: Process?

    struct VideoInfo {
        let title: String
        let duration: Int
        let uploader: String
        let thumbnail: String
    }

    // MARK: - Download

    func download(url: String, quality: String, format: String, audioOnly: Bool, category: String) {
        guard !isDownloading else { return }

        isDownloading = true
        progress = 0
        statusText = "Iniciando..."
        logLines = []

        let baseDir = NSHomeDirectory() + "/Downloads/YTool"
        let platform = detectPlatform(url: url)
        let outputDir = "\(baseDir)/\(platform)/\(category)"

        // Create output directory
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let outputTemplate = "\(outputDir)/%(title)s.%(ext)s"

        var args = ["--newline", "--no-playlist", "-o", outputTemplate]

        if audioOnly {
            args += ["-x", "--audio-format", "mp3"]
        } else if quality != "best" {
            let height = quality.replacingOccurrences(of: "p", with: "")
            args += ["-f", "bestvideo[height<=\(height)]+bestaudio/best[height<=\(height)]", "--merge-output-format", format]
        } else {
            args += ["-f", "bestvideo+bestaudio/best", "--merge-output-format", format]
        }

        args.append(url)

        Task {
            await runYtdlp(args: args, url: url, outputDir: outputDir, category: category)
        }
    }

    func cancel() {
        process?.terminate()
        isDownloading = false
        statusText = "Cancelado"
    }

    // MARK: - Private

    private func runYtdlp(args: [String], url: String, outputDir: String, category: String) async {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["yt-dlp"] + args

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        self.process = proc

        do {
            try proc.run()
        } catch {
            statusText = "Erro: yt-dlp não encontrado"
            isDownloading = false
            return
        }

        let handle = pipe.fileHandleForReading

        // Read output line by line
        for try await line in handle.bytes.lines {
            await MainActor.run {
                parseLine(line)
            }
        }

        proc.waitUntilExit()

        await MainActor.run {
            if proc.terminationStatus == 0 {
                progress = 100
                statusText = "Concluído!"
                history.insert(DownloadHistoryItem(
                    url: url,
                    title: "",
                    outputDir: outputDir,
                    timestamp: Date(),
                    category: category
                ), at: 0)
            } else if statusText != "Cancelado" {
                statusText = "Erro (código \(proc.terminationStatus))"
            }
            isDownloading = false
        }
    }

    private func parseLine(_ line: String) {
        // Parse yt-dlp progress: [download]  45.2% of 120.5MiB at 5.2MiB/s ETA 00:15
        let pattern = #"\[download\]\s+([\d.]+)%\s+of\s+(\S+)\s+at\s+(\S+)\s+ETA\s+(\S+)"#
        if let match = line.range(of: pattern, options: .regularExpression) {
            let matched = String(line[match])
            let parts = matched.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2, let pct = Double(parts[1].replacingOccurrences(of: "%", with: "")) {
                progress = pct
                statusText = "Baixando... \(parts.count > 5 ? parts[5] : "")"
            }
        } else {
            logLines.append(line)
            if logLines.count > 50 { logLines.removeFirst() }
        }
    }

    private func detectPlatform(url: String) -> String {
        if url.contains("youtube.com") || url.contains("youtu.be") { return "youtube" }
        if url.contains("instagram.com") { return "instagram" }
        return "other"
    }
}
