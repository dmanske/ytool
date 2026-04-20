import SwiftUI
import AppKit

// MARK: - Reliable NSTextField wrapper

struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onCommit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.allowsEditingTextAttributes = false
        field.font = .systemFont(ofSize: 16)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        context.coordinator.field = field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = field.window, window.firstResponder != field.currentEditor() {
                window.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        guard !context.coordinator.isSyncing else { return }
        if field.stringValue != text { field.stringValue = text }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        var isSyncing = false
        weak var field: NSTextField?
        init(_ parent: FocusableTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            isSyncing = true
            parent.text = field.stringValue
            isSyncing = false
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.onCommit(); return true }
            return false
        }
    }
}

// MARK: - Browser Detection

func detectDefaultBrowser() -> String {
    if let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)?.lastPathComponent.lowercased() {
        if app.contains("firefox") { return "firefox" }
        if app.contains("safari")  { return "safari" }
        if app.contains("brave")   { return "brave" }
        if app.contains("edge")    { return "edge" }
        if app.contains("chrome") || app.contains("chromium") { return "chrome" }
    }
    for app in NSWorkspace.shared.runningApplications {
        let name = app.localizedName?.lowercased() ?? ""
        if name.contains("firefox") { return "firefox" }
        if name.contains("chrome")  { return "chrome" }
        if name.contains("brave")   { return "brave" }
        if name.contains("edge")    { return "edge" }
    }
    return "safari"
}

// MARK: - Main Download View

struct SingleDownloadView: View {
    @EnvironmentObject private var manager: DownloadManager

    @State private var url = ""
    @State private var quality = "best"
    @State private var format = "mp4"
    @State private var audioOnly = false
    @State private var category = "Clips"
    @State private var customFilename = ""
    @State private var subtitles = false
    @State private var subLangs = "en,pt"
    @State private var showOptions = false

    private let categories = [
        "Clips", "Música", "Tutoriais", "Filmes", "Séries",
        "Podcasts", "Gameplay", "Educação", "Vlogs", "Outros"
    ]

    var body: some View {
        ZStack(alignment: .top) {
            gradientBackground
            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 36)

                    // Setup banner (when dependencies are missing/installing)
                    if !manager.dependenciesReady {
                        setupBanner.padding(.horizontal, 28)
                    }

                    controlsCard
                    if manager.isDownloading || manager.progress > 0 {
                        progressCard.padding(.horizontal, 28)
                    }
                    if let item = manager.lastDownload, !manager.isDownloading {
                        completionCard(item).padding(.horizontal, 28)
                    }
                    if !manager.history.isEmpty {
                        historySection.padding(.horizontal, 28)
                    }
                    Spacer().frame(height: 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Completion Preview Card

    private func completionCard(_ item: DownloadHistoryItem) -> some View {
        HStack(spacing: 16) {
            // Thumbnail
            Group {
                if !item.thumbnailURL.isEmpty, let u = URL(string: item.thumbnailURL) {
                    AsyncImage(url: u) { phase in
                        if case .success(let img) = phase {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle().fill(Color.green.opacity(0.15))
                                .overlay(Image(systemName: "checkmark.circle.fill")
                                    .font(.title).foregroundStyle(.green))
                        }
                    }
                } else {
                    Rectangle().fill(Color.green.opacity(0.15))
                        .overlay(Image(systemName: "checkmark.circle.fill")
                            .font(.title).foregroundStyle(.green))
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 6) {
                Label("Download concluído!", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.green)
                Text(item.title.isEmpty ? "Arquivo salvo" : item.title)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.outputDir)
                    } label: {
                        Label("Ver no Finder", systemImage: "folder")
                            .font(.caption).fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())

                    Button {
                        if let files = try? FileManager.default.contentsOfDirectory(atPath: item.outputDir),
                           let file = files.first {
                            let full = (item.outputDir as NSString).appendingPathComponent(file)
                            NSWorkspace.shared.open(URL(fileURLWithPath: full))
                        }
                    } label: {
                        Label("Reproduzir", systemImage: "play.fill")
                            .font(.caption).fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .clipShape(Capsule())
                }
            }

            Spacer()

            Button { manager.lastDownload = nil } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.tertiary)
            }.buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.green.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.green.opacity(0.25), lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.4), value: manager.lastDownload != nil)
    }

    // MARK: - Setup Banner

    @State private var showTerminalTip = false

    private var setupBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: manager.isInstalling
                      ? "arrow.down.circle" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(manager.isInstalling ? .blue : .orange)
                    .symbolEffect(.pulse, isActive: manager.isInstalling)

                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.isInstalling
                         ? "Instalando dependências..."
                         : "Dependências não encontradas")
                        .font(.subheadline).fontWeight(.semibold)
                    Text(manager.isInstalling
                         ? manager.statusText
                         : "yt-dlp e ffmpeg são necessários para baixar vídeos")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                if !manager.isInstalling {
                    Button {
                        manager.installYtdlp()
                    } label: {
                        Label("Instalar agora", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }

            if manager.isInstalling && manager.progress > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.2)).frame(height: 5)
                        RoundedRectangle(cornerRadius: 3).fill(Color.blue)
                            .frame(width: geo.size.width * manager.progress / 100, height: 5)
                            .animation(.linear(duration: 0.3), value: manager.progress)
                    }
                }.frame(height: 5)
            }

            // Version status
            if let ver = manager.ytdlpVersion {
                HStack(spacing: 6) {
                    Image(systemName: ver.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(ver.isEmpty ? .red : .green)
                        .font(.caption)
                    Text(ver.isEmpty
                         ? "yt-dlp: não encontrado"
                         : "yt-dlp \(ver) ✓")
                        .font(.caption).foregroundStyle(ver.isEmpty ? .red : .green)
                    Spacer()
                    Button { manager.checkYtdlpVersion() } label: {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }

            // Terminal fallback
            DisclosureGroup(isExpanded: $showTerminalTip) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ou instale manualmente pelo Terminal:")
                        .font(.caption).foregroundStyle(.secondary)
                    terminalCommand("brew install yt-dlp ffmpeg")
                    Text("Se não tiver Homebrew:")
                        .font(.caption).foregroundStyle(.tertiary)
                    terminalCommand("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                }
                .padding(.top, 6)
            } label: {
                Text("Instalar pelo Terminal (alternativa)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1))
    }

    private func terminalCommand(_ cmd: String) -> some View {
        HStack(spacing: 8) {
            Text(cmd)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cmd, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copiar")
        }
        .padding(10)
        .background(Color(.textBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Gradient Background

    private var gradientBackground: some View {
        ZStack {
            Color(.windowBackgroundColor)
            Circle()
                .fill(Color.red.opacity(0.30))
                .frame(width: 550)
                .blur(radius: 100)
                .offset(x: -200, y: -170)
            Circle()
                .fill(Color.blue.opacity(0.16))
                .frame(width: 460)
                .blur(radius: 100)
                .offset(x: 300, y: -140)
            Circle()
                .fill(Color.pink.opacity(0.18))
                .frame(width: 380)
                .blur(radius: 80)
                .offset(x: 80, y: 60)
        }
        .ignoresSafeArea()
    }

    // MARK: - Controls Card

    private var controlsCard: some View {
        VStack(spacing: 20) {
            urlBar
            qualityFormatRow
            downloadButton
            if showOptions { optionsExtra }
        }
        .padding(.horizontal, 26).padding(.vertical, 22)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 24, y: 4)
        .padding(.horizontal, 28)
    }

    // MARK: - URL Bar

    private var urlBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "link")
                .foregroundStyle(.tertiary)
                .frame(width: 44)
                .font(.system(size: 16))

            FocusableTextField(
                text: $url,
                placeholder: "Cole o link aqui...",
                onCommit: startDownload
            )

            if !url.isEmpty {
                Button { url = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 6)
                }.buttonStyle(.plain)
            }

            Button {
                if let s = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    url = s
                }
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(.red)
                    .font(.system(size: 17))
                    .padding(.trailing, 16)
            }
            .buttonStyle(.plain)
            .help("Colar da área de transferência")
        }
        .frame(height: 56)
        .background(Color(.textBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28)
            .strokeBorder(Color(.separatorColor).opacity(0.5), lineWidth: 1))
    }

    // MARK: - Quality + Format Pills

    private var qualityFormatRow: some View {
        HStack(spacing: 0) {
            // Quality label
            Text("QUALIDADE")
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.secondary).tracking(0.5)
                .padding(.trailing, 8)

            // Quality pills
            HStack(spacing: 6) {
                ForEach([("Melhor","best"),("4K","2160p"),("1080p","1080p"),("720p","720p"),("480p","480p")], id: \.1) { label, val in
                    pill(label, selected: quality == val && !audioOnly) {
                        quality = val; audioOnly = false
                    }
                }
            }

            Divider().frame(height: 24).padding(.horizontal, 14)

            // Format label
            Text("FORMATO")
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.secondary).tracking(0.5)
                .padding(.trailing, 8)

            // Format pills
            HStack(spacing: 6) {
                pill("MP4",  selected: !audioOnly && format == "mp4")  { audioOnly = false; format = "mp4" }
                pill("WebM", selected: !audioOnly && format == "webm") { audioOnly = false; format = "webm" }
                pill("MKV",  selected: !audioOnly && format == "mkv")  { audioOnly = false; format = "mkv" }
                pill("MP3",  selected: audioOnly)                      { audioOnly = true;  format = "mp3" }
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3)) { showOptions.toggle() }
            } label: {
                Image(systemName: showOptions ? "slider.horizontal.3" : "slider.horizontal.3")
                    .foregroundStyle(showOptions ? Color.red : .secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Opções")
        }
    }

    private func pill(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline).fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(selected ? Color.red : Color(.controlBackgroundColor))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
                .animation(.easeInOut(duration: 0.15), value: selected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Options (expandable)

    private var optionsExtra: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Categoria", systemImage: "folder.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }.pickerStyle(.menu).labelsHidden().frame(maxWidth: 140)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Nome do arquivo", systemImage: "pencil")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Título do vídeo (padrão)", text: $customFilename)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("Legendas", systemImage: "text.quote")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Toggle("", isOn: $subtitles).toggleStyle(.switch).tint(.red).labelsHidden()
                        if subtitles {
                            TextField("en,pt", text: $subLangs)
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 80).font(.caption)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        HStack(spacing: 10) {
            Button { startDownload() } label: {
                HStack(spacing: 10) {
                    if manager.isDownloading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill").font(.title3)
                    }
                    Text(manager.isInstalling ? "Instalando..." : manager.isDownloading ? "Baixando..." : "Baixar")
                        .font(.title3).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(url.isEmpty || manager.isDownloading || manager.isInstalling)
            .clipShape(RoundedRectangle(cornerRadius: 27))

            if manager.isDownloading && !manager.isInstalling {
                Button { manager.cancel() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancelar")
            }
        }
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    if manager.isDownloading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: manager.progress >= 100
                              ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(manager.progress >= 100 ? .green : .orange)
                    }
                    Text(manager.statusText).font(.subheadline).fontWeight(.medium)
                }
                Spacer()
                Text("\(Int(manager.progress))%")
                    .font(.title3).fontWeight(.bold).monospacedDigit()
                    .foregroundStyle(.red)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.15)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4).fill(Color.red)
                        .frame(width: geo.size.width * manager.progress / 100, height: 6)
                        .animation(.linear(duration: 0.3), value: manager.progress)
                }
            }
            .frame(height: 6)

            if !manager.logLines.isEmpty {
                DisclosureGroup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(manager.logLines.suffix(12), id: \.self) { line in
                                Text(line).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxHeight: 100)
                } label: {
                    Text("Log").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - History Grid

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recentes")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Button { manager.clearHistory() } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help("Limpar histórico")
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 175), spacing: 12)],
                spacing: 12
            ) {
                ForEach(manager.history) { item in
                    historyCard(item)
                }
            }
        }
    }

    private func historyCard(_ item: DownloadHistoryItem) -> some View {
        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.outputDir)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                Group {
                    if !item.thumbnailURL.isEmpty, let u = URL(string: item.thumbnailURL) {
                        AsyncImage(url: u) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                thumbnailPlaceholder
                            }
                        }
                    } else {
                        thumbnailPlaceholder
                    }
                }
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 12, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 12
                ))

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "Download" : item.title)
                        .font(.caption).fontWeight(.medium)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    HStack {
                        Text(item.category)
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            manager.history.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "trash").font(.caption2).foregroundStyle(.quaternary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color(.separatorColor).opacity(0.35))
            .overlay(Image(systemName: "film").foregroundStyle(.quaternary).font(.title2))
    }

    // MARK: - Actions

    private func startDownload() {
        guard !url.isEmpty, !manager.isDownloading, !manager.isInstalling else { return }
        let browser = detectDefaultBrowser()
        manager.download(
            url: url, quality: quality, format: format,
            audioOnly: audioOnly, category: category,
            customFilename: customFilename,
            subtitles: subtitles, subLangs: subLangs,
            cookieBrowser: browser
        )
    }
}
