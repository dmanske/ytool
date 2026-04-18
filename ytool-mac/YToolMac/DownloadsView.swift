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
        field.font = .systemFont(ofSize: 14)
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
    let platform: String
    let platformName: String
    let accentColor: Color

    @EnvironmentObject private var manager: DownloadManager

    @State private var url = ""
    @State private var quality = "best"
    @State private var format = "mp4"
    @State private var audioOnly = false
    @State private var category = "Clips"
    @State private var customFilename = ""
    @State private var subtitles = false
    @State private var subLangs = "en,pt"
    @State private var inspectError: String?
    @State private var videoInfo: VideoInfo?
    @State private var selectedFormatID: String?

    private let qualities: [(label: String, value: String)] = [
        ("Melhor disponível", "best"), ("4K Ultra HD", "2160p"),
        ("1080p Full HD", "1080p"), ("720p HD", "720p"),
        ("480p", "480p"), ("360p", "360p")
    ]
    private let formats: [(label: String, value: String)] = [
        ("MP4 (recomendado)", "mp4"), ("WebM", "webm"), ("MKV", "mkv")
    ]
    private let categories = [
        "Música", "Tutoriais", "Filmes", "Séries", "Clips",
        "Podcasts", "Gameplay", "Educação", "Vlogs", "Outros"
    ]

    var body: some View {
        HSplitView {
            mainPanel
                .frame(minWidth: 500, idealWidth: 640)
            historyPanel
                .frame(minWidth: 180, idealWidth: 220)
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Main Panel

    private var mainPanel: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroHeader
                VStack(spacing: 16) {
                    urlCard
                    if let info = videoInfo { previewCard(info) }
                    if let fmts = videoInfo?.formats, !fmts.isEmpty { formatsCard(fmts) }
                    optionsCard
                    downloadButton
                    if manager.isDownloading || manager.progress > 0 { progressCard }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: platform == "youtube"
                    ? [accentColor.opacity(0.85), accentColor.opacity(0.4)]
                    : [Color.purple.opacity(0.7), accentColor.opacity(0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 90)

            HStack(spacing: 12) {
                Image(systemName: platform == "youtube" ? "play.rectangle.fill" : "camera.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(platformName)
                        .font(.title2).fontWeight(.bold).foregroundStyle(.white)
                    Text(platform == "youtube" ? "Vídeos, Shorts, Músicas — até 4K" : "Posts, Reels e Stories públicos")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
    }

    // MARK: - URL Card

    private var urlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("URL DO VÍDEO")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(0.5)

            HStack(spacing: 0) {
                Image(systemName: "link")
                    .foregroundStyle(.tertiary)
                    .frame(width: 36)

                FocusableTextField(
                    text: $url,
                    placeholder: "Cole o link aqui...",
                    onCommit: startDownload
                )

                if !url.isEmpty {
                    Button { clearAll() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .padding(.trailing, 8)
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 20).padding(.trailing, 8)

                Button {
                    if let s = NSPasteboard.general.string(forType: .string)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                        url = s
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(accentColor)
                        .padding(.trailing, 10)
                }
                .buttonStyle(.plain)
                .help("Colar da área de transferência")
            }
            .frame(height: 46)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separatorColor), lineWidth: 1))

            if let err = inspectError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Preview Card

    private func previewCard(_ info: VideoInfo) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: info.thumbnail)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentColor.opacity(0.1))
                    .overlay(Image(systemName: "photo").foregroundStyle(.quaternary))
            }
            .frame(width: 140, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(info.title)
                    .font(.subheadline).fontWeight(.semibold).lineLimit(2)
                HStack(spacing: 12) {
                    if !info.uploader.isEmpty {
                        Label(info.uploader, systemImage: "person.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if info.duration > 0 {
                        Label(info.durationFormatted, systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !info.formats.isEmpty {
                    Text("\(info.formats.count) formatos · \(info.formats.filter { $0.kind != .audioOnly }.count) vídeo · \(info.formats.filter { $0.kind == .audioOnly }.count) áudio")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accentColor.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Formats Card

    private func formatsCard(_ fmts: [VideoFormat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FORMATOS DISPONÍVEIS")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(.secondary).tracking(0.5)
                Spacer()
                Text("\(fmts.count) disponíveis")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(fmts) { fmt in
                        Button {
                            selectedFormatID = selectedFormatID == fmt.id ? nil : fmt.id
                        } label: {
                            HStack(spacing: 10) {
                                Text(fmt.kind.emoji).frame(width: 22)
                                Text(fmt.label).font(.caption).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if selectedFormatID == fmt.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(accentColor).font(.caption)
                                }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selectedFormatID == fmt.id
                                ? accentColor.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separatorColor), lineWidth: 1))

            if selectedFormatID != nil {
                Label("Formato específico selecionado — opções abaixo ignoradas", systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Options Card

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Quality row
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.caption).foregroundStyle(accentColor.opacity(0.8))
                    Text("QUALIDADE").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).tracking(0.5)
                }
                HStack(spacing: 8) {
                    ForEach([
                        ("Melhor", "best",   "crown.fill"),
                        ("4K",    "2160p",  "4.square.fill"),
                        ("1080p", "1080p",  "tv"),
                        ("720p",  "720p",   "display"),
                        ("480p",  "480p",   "iphone"),
                    ], id: \.1) { label, value, icon in
                        qualityPill(label: label, value: value, icon: icon, binding: $quality)
                    }
                }
            }

            Divider()

            // Format row
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill").font(.caption).foregroundStyle(accentColor.opacity(0.8))
                    Text("FORMATO").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).tracking(0.5)
                }
                HStack(spacing: 8) {
                    formatPill(label: "MP4", icon: "film.fill",  isAudio: false, fmtValue: "mp4")
                    formatPill(label: "WebM", icon: "play.fill", isAudio: false, fmtValue: "webm")
                    formatPill(label: "MKV",  icon: "archivebox.fill", isAudio: false, fmtValue: "mkv")
                    formatPill(label: "MP3",  icon: "music.note", isAudio: true,  fmtValue: "mp3")
                }
            }

            Divider()

            // Category + extras
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill").font(.caption).foregroundStyle(accentColor.opacity(0.8))
                        Text("CATEGORIA").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).tracking(0.5)
                    }
                    Picker("", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }.pickerStyle(.menu).labelsHidden().frame(maxWidth: 140)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote").font(.caption).foregroundStyle(accentColor.opacity(0.8))
                        Text("LEGENDAS").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).tracking(0.5)
                    }
                    HStack {
                        Toggle("", isOn: $subtitles).toggleStyle(.switch).tint(accentColor).labelsHidden()
                        if subtitles {
                            TextField("en,pt", text: $subLangs)
                                .textFieldStyle(.roundedBorder).frame(maxWidth: 80).font(.caption)
                        }
                    }
                }
            }

            Divider()

            // Filename
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "pencil").font(.caption).foregroundStyle(accentColor.opacity(0.8))
                    Text("NOME DO ARQUIVO").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).tracking(0.5)
                }
                TextField("Deixe vazio para usar o título do vídeo", text: $customFilename)
                    .textFieldStyle(.roundedBorder).font(.callout)
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separatorColor), lineWidth: 1))
    }

    private func qualityPill(label: String, value: String, icon: String, binding: Binding<String>) -> some View {
        let selected = binding.wrappedValue == value
        return Button {
            binding.wrappedValue = value
            if value == "2160p" || value == "1080p" || value == "720p" || value == "480p" || value == "best" {
                audioOnly = false
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label).font(.caption).fontWeight(selected ? .semibold : .regular)
            }
            .frame(width: 58, height: 48)
            .background(selected ? accentColor : Color(.controlBackgroundColor))
            .foregroundStyle(selected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? accentColor : Color(.separatorColor), lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    private func formatPill(label: String, icon: String, isAudio: Bool, fmtValue: String) -> some View {
        let selected = isAudio ? audioOnly : (!audioOnly && format == fmtValue)
        return Button {
            if isAudio {
                audioOnly = true
                format = "mp3"
            } else {
                audioOnly = false
                format = fmtValue
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label).font(.caption).fontWeight(selected ? .semibold : .regular)
            }
            .frame(width: 58, height: 48)
            .background(selected ? accentColor : Color(.controlBackgroundColor))
            .foregroundStyle(selected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? accentColor : Color(.separatorColor), lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        HStack(spacing: 10) {
            Button {
                startDownload()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").font(.body)
                    Text("Baixar").fontWeight(.semibold).font(.title3)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(url.isEmpty || manager.isDownloading)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if manager.isDownloading {
                Button {
                    manager.cancel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancelar")
                    }
                    .frame(height: 44)
                }
                .buttonStyle(.bordered)
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        Image(systemName: manager.progress == 100
                              ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(manager.progress == 100 ? .green : .orange)
                            .font(.caption)
                    }
                    Text(manager.statusText).font(.subheadline).fontWeight(.medium)
                }
                Spacer()
                Text("\(Int(manager.progress))%")
                    .font(.title3).fontWeight(.bold).monospacedDigit()
                    .foregroundStyle(accentColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentColor.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accentColor)
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
                    }.frame(maxHeight: 120)
                } label: {
                    Text("Log de saída").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separatorColor), lineWidth: 1))
    }

    // MARK: - History Panel

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Recentes")
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                if !manager.history.isEmpty {
                    Button { manager.clearHistory() } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Limpar histórico")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color(.windowBackgroundColor))

            Divider()

            if manager.history.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("Nenhum download ainda")
                        .font(.caption).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(manager.history) { item in
                            historyRow(item)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func historyRow(_ item: DownloadHistoryItem) -> some View {
        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.outputDir)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.url.contains("instagram")
                          ? Color.pink.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: item.url.contains("instagram")
                              ? "camera.fill" : "play.rectangle.fill")
                            .font(.caption)
                            .foregroundStyle(item.url.contains("instagram") ? .pink : .red)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "Download" : item.title)
                        .font(.caption).fontWeight(.medium).lineLimit(3)
                        .foregroundStyle(.primary)
                    Text(item.category)
                        .font(.caption2)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(accentColor.opacity(0.1))
                        .foregroundStyle(accentColor)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 0)
                Image(systemName: "folder").font(.caption2).foregroundStyle(.quaternary)
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func clearAll() {
        url = ""
        videoInfo = nil
        selectedFormatID = nil
        inspectError = nil
    }

    private func startDownload() {
        guard !url.isEmpty, !manager.isDownloading else { return }
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
