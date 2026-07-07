import SwiftUI
import AppKit

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

// MARK: - Design tokens

private enum YT {
    static let red = Color(red: 0.92, green: 0.20, blue: 0.18)
    static let redDark = Color(red: 0.72, green: 0.08, blue: 0.12)
    static var gradient: LinearGradient {
        LinearGradient(colors: [red, redDark], startPoint: .top, endPoint: .bottom)
    }
    static let cardRadius: CGFloat = 16
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
    @FocusState private var urlFocused: Bool

    private let categories = [
        "Clips", "Música", "Tutoriais", "Filmes", "Séries",
        "Podcasts", "Gameplay", "Educação", "Vlogs", "Outros"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if !manager.dependenciesReady {
                    setupBanner
                }

                downloadCard

                if manager.isDownloading || manager.progress > 0 {
                    progressCard
                }

                if let item = manager.lastDownload, !manager.isDownloading {
                    completionCard(item)
                }

                if !manager.history.isEmpty {
                    historySection
                }
            }
            .frame(maxWidth: 780)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .background(backgroundView)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { urlFocused = true }
        }
    }

    private var backgroundView: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [YT.red.opacity(0.07), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(YT.gradient)
                    .frame(width: 46, height: 46)
                    .shadow(color: YT.red.opacity(0.35), radius: 8, y: 3)
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("YTool")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Baixe vídeos do YouTube e Instagram")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let ver = manager.ytdlpVersion, !ver.isEmpty {
                Label("yt-dlp \(ver)", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Download Card

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            urlField

            VStack(alignment: .leading, spacing: 12) {
                optionRow(label: "Qualidade") {
                    ForEach([("Melhor", "best"), ("4K", "2160p"), ("1080p", "1080p"),
                             ("720p", "720p"), ("480p", "480p")], id: \.1) { label, val in
                        pill(label, selected: quality == val && !audioOnly) {
                            quality = val
                            audioOnly = false
                        }
                    }
                }
                optionRow(label: "Formato") {
                    pill("MP4",  selected: !audioOnly && format == "mp4")  { audioOnly = false; format = "mp4" }
                    pill("WebM", selected: !audioOnly && format == "webm") { audioOnly = false; format = "webm" }
                    pill("MKV",  selected: !audioOnly && format == "mkv")  { audioOnly = false; format = "mkv" }
                    pill("MP3",  selected: audioOnly, icon: "music.note")  { audioOnly = true;  format = "mp3" }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3)) { showOptions.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Opções")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(showOptions ? 180 : 0))
                        }
                        .font(.caption)
                        .foregroundStyle(showOptions ? YT.red : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if showOptions {
                extraOptions
            }

            downloadButton
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: YT.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: YT.cardRadius)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
    }

    // MARK: - URL Field

    private var urlField: some View {
        HStack(spacing: 10) {
            Image(systemName: "link")
                .font(.system(size: 14))
                .foregroundStyle(urlFocused ? YT.red : .secondary)

            TextField("Cole o link do vídeo aqui…", text: $url)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($urlFocused)
                .onSubmit(startDownload)

            if !url.isEmpty {
                Button { url = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Limpar")
            }

            Divider().frame(height: 16)

            Button {
                if let s = NSPasteboard.general.string(forType: .string)?
                    .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    url = s
                }
            } label: {
                Label("Colar", systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(YT.red)
            }
            .buttonStyle(.plain)
            .help("Colar da área de transferência")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(urlFocused ? YT.red.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.7),
                          lineWidth: urlFocused ? 1.5 : 1))
        .animation(.easeInOut(duration: 0.15), value: urlFocused)
    }

    // MARK: - Option rows + pills

    private func optionRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            content()
        }
    }

    private func pill(_ label: String, selected: Bool, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 10)) }
                Text(label)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(Capsule().fill(selected ? YT.red : Color.primary.opacity(0.055)))
            .foregroundStyle(selected ? .white : .primary)
            .animation(.easeInOut(duration: 0.15), value: selected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Extra Options

    private var extraOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Categoria", systemImage: "folder")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .frame(width: 130)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Nome do arquivo", systemImage: "pencil")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Título do vídeo (padrão)", text: $customFilename)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Legendas", systemImage: "captions.bubble")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Toggle("", isOn: $subtitles)
                            .toggleStyle(.switch).controlSize(.small)
                            .tint(YT.red).labelsHidden()
                        if subtitles {
                            TextField("en,pt", text: $subLangs)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80).font(.caption)
                        }
                    }
                }
                Spacer()
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Download Button

    private var downloadButton: some View {
        HStack(spacing: 10) {
            Button(action: startDownload) {
                HStack(spacing: 8) {
                    if manager.isDownloading {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text(manager.isInstalling ? "Instalando…" : manager.isDownloading ? "Baixando…" : "Baixar")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isDisabled ? AnyShapeStyle(Color.gray.opacity(0.45)) : AnyShapeStyle(YT.gradient))
                )
                .shadow(color: isDisabled ? .clear : YT.red.opacity(0.3), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)

            if manager.isDownloading && !manager.isInstalling {
                Button { manager.cancel() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancelar")
            }
        }
    }

    private var isDisabled: Bool {
        url.isEmpty || manager.isDownloading || manager.isInstalling
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    if manager.isDownloading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: manager.progress >= 100
                              ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(manager.progress >= 100 ? .green : .orange)
                    }
                    Text(manager.statusText)
                        .font(.subheadline).fontWeight(.medium)
                }
                Spacer()
                Text("\(Int(manager.progress))%")
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(YT.red)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(YT.red.opacity(0.12)).frame(height: 6)
                    Capsule().fill(YT.gradient)
                        .frame(width: max(6, geo.size.width * manager.progress / 100), height: 6)
                        .animation(.linear(duration: 0.3), value: manager.progress)
                }
            }
            .frame(height: 6)

            if !manager.logLines.isEmpty {
                DisclosureGroup {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(manager.logLines.suffix(12), id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                } label: {
                    Text("Detalhes").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: YT.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: YT.cardRadius)
            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1))
    }

    // MARK: - Completion Card

    private func completionCard(_ item: DownloadHistoryItem) -> some View {
        HStack(spacing: 14) {
            thumbnail(for: item.thumbnailURL, fallbackIcon: "checkmark.circle.fill", fallbackColor: .green)
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 5) {
                Label("Download concluído", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.green)
                Text(item.title.isEmpty ? "Arquivo salvo" : item.title)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.outputDir)
                    } label: {
                        Label("Ver no Finder", systemImage: "folder")
                            .font(.caption).fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        if let files = try? FileManager.default.contentsOfDirectory(atPath: item.outputDir),
                           let file = files.first(where: { !$0.hasPrefix(".") }) {
                            let full = (item.outputDir as NSString).appendingPathComponent(file)
                            NSWorkspace.shared.open(URL(fileURLWithPath: full))
                        }
                    } label: {
                        Label("Reproduzir", systemImage: "play.fill")
                            .font(.caption).fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
            }

            Spacer()

            Button { manager.lastDownload = nil } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: YT.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: YT.cardRadius)
            .strokeBorder(Color.green.opacity(0.25), lineWidth: 1))
        .transition(.move(edge: .top).combined(with: .opacity))
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
                         ? "Instalando dependências…"
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
                        Capsule().fill(Color.blue.opacity(0.2)).frame(height: 5)
                        Capsule().fill(Color.blue)
                            .frame(width: geo.size.width * manager.progress / 100, height: 5)
                            .animation(.linear(duration: 0.3), value: manager.progress)
                    }
                }
                .frame(height: 5)
            }

            if let ver = manager.ytdlpVersion {
                HStack(spacing: 6) {
                    Image(systemName: ver.isEmpty ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(ver.isEmpty ? Color.red : Color.green)
                        .font(.caption)
                    Text(ver.isEmpty ? "yt-dlp: não encontrado" : "yt-dlp \(ver)")
                        .font(.caption)
                        .foregroundStyle(ver.isEmpty ? Color.red : Color.green)
                    Spacer()
                    Button { manager.checkYtdlpVersion() } label: {
                        Image(systemName: "arrow.clockwise").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

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
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: YT.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: YT.cardRadius)
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
        .background(Color(nsColor: .textBackgroundColor).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recentes")
                    .font(.title3).fontWeight(.bold)
                Spacer()
                Button {
                    manager.clearHistory()
                } label: {
                    Label("Limpar", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Limpar histórico")
            }
            .padding(.top, 8)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12)],
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
                thumbnail(for: item.thumbnailURL, fallbackIcon: "film", fallbackColor: .secondary)
                    .frame(height: 88)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title.isEmpty ? "Download" : item.title)
                        .font(.caption).fontWeight(.medium)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(item.category)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            manager.history.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundStyle(.quaternary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared thumbnail helper

    @ViewBuilder
    private func thumbnail(for urlString: String, fallbackIcon: String, fallbackColor: Color) -> some View {
        if !urlString.isEmpty, let u = URL(string: urlString) {
            AsyncImage(url: u) { phase in
                if case .success(let img) = phase {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    thumbnailPlaceholder(icon: fallbackIcon, color: fallbackColor)
                }
            }
        } else {
            thumbnailPlaceholder(icon: fallbackIcon, color: fallbackColor)
        }
    }

    private func thumbnailPlaceholder(icon: String, color: Color) -> some View {
        Rectangle()
            .fill(color.opacity(0.12))
            .overlay(Image(systemName: icon).foregroundStyle(color.opacity(0.6)).font(.title3))
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
