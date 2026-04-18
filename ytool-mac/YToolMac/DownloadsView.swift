import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject var manager: DownloadManager
    @State private var url: String = ""
    @State private var quality: String = "best"
    @State private var format: String = "mp4"
    @State private var audioOnly: Bool = false
    @State private var category: String = "Música"

    private let qualities = ["best", "1080p", "720p", "480p", "360p"]
    private let formats = ["mp4", "webm", "mkv"]
    private let categories = ["Música", "Tutoriais", "Filmes", "Outros"]

    var body: some View {
        HSplitView {
            // Left: form + progress
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("👋 Bem-vindo ao YTool")
                            .font(.title)
                            .fontWeight(.semibold)
                        Text("Baixe vídeos e áudios do YouTube e Instagram")
                            .foregroundStyle(.secondary)
                    }

                    // URL field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("URL DO VÍDEO")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Cole a URL do YouTube ou Instagram aqui...", text: $url)
                                .textFieldStyle(.roundedBorder)
                            Button("Limpar") {
                                url = ""
                                manager.videoInfo = nil
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            Text("Plataformas:")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            CapsuleTag("YouTube")
                            CapsuleTag("Instagram (público)")
                        }
                    }

                    // Options grid
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            LabeledPicker("QUALIDADE", selection: $quality, options: qualities)
                            LabeledPicker("FORMATO", selection: $format, options: formats)
                            LabeledPicker("CATEGORIA", selection: $category, options: categories)
                        }
                    }

                    Toggle("Somente áudio (MP3)", isOn: $audioOnly)
                        .toggleStyle(.checkbox)

                    // Buttons
                    HStack(spacing: 12) {
                        Button {
                            startDownload()
                        } label: {
                            Label("Baixar", systemImage: "arrow.down.circle")
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(url.isEmpty || manager.isDownloading)
                        .keyboardShortcut(.return, modifiers: .command)

                        if manager.isDownloading {
                            Button("Cancelar") {
                                manager.cancel()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Progress
                    if manager.isDownloading || manager.progress > 0 {
                        ProgressCard(manager: manager)
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 500)

            // Right: history
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("DOWNLOADS RECENTES")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !manager.history.isEmpty {
                        Button("Limpar") {
                            manager.history.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if manager.history.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundStyle(.quaternary)
                        Text("Nenhum download ainda")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(manager.history) { item in
                        HistoryRow(item: item)
                    }
                    .listStyle(.inset)
                }
            }
            .padding(16)
            .frame(minWidth: 300, idealWidth: 350)
        }
    }

    private func startDownload() {
        manager.download(
            url: url,
            quality: quality,
            format: format,
            audioOnly: audioOnly,
            category: category
        )
    }
}

// MARK: - Subviews

struct CapsuleTag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}

struct LabeledPicker: View {
    let label: String
    @Binding var selection: String
    let options: [String]

    init(_ label: String, selection: Binding<String>, options: [String]) {
        self.label = label
        self._selection = selection
        self.options = options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { Text($0) }
            }
            .labelsHidden()
            .frame(minWidth: 120)
        }
    }
}

struct ProgressCard: View {
    @ObservedObject var manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(manager.statusText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(manager.progress))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                    .monospacedDigit()
            }
            ProgressView(value: manager.progress, total: 100)
                .tint(.red)
            if !manager.logLines.isEmpty {
                Text(manager.logLines.suffix(3).joined(separator: "\n"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                    .monospaced()
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct HistoryRow: View {
    let item: DownloadHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title.isEmpty ? item.url : item.title)
                .font(.subheadline)
                .lineLimit(1)
            Text(item.outputDir)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.outputDir)
        }
    }
}
