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

// MARK: - Campo de texto nativo (NSTextField) — garante Cmd+V/Cmd+C/Cmd+X sempre funcionais

struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onCommit: () -> Void = {}
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 15)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false
        // Foca uma única vez quando a janela abre
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = field.window, window.firstResponder is NSWindow || window.firstResponder == nil {
                window.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isSyncing else { return }
        if field.stringValue != text { field.stringValue = text }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        var isSyncing = false
        init(_ parent: FocusableTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            isSyncing = true
            parent.text = field.stringValue
            isSyncing = false
        }
        func controlTextDidBeginEditing(_ obj: Notification) { parent.onFocusChange(true) }
        func controlTextDidEndEditing(_ obj: Notification) { parent.onFocusChange(false) }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { parent.onCommit(); return true }
            return false
        }
    }
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
    @State private var showOptions = true
    @State private var urlFocused = false

    // Video inspection (preview)
    @State private var videoInfo: VideoInfo?
    @State private var isInspecting = false
    @State private var inspectError: String?
    @State private var inspectTask: Task<Void, Never>?

    private let categories = [
        "Clips", "Música", "Tutoriais", "Filmes", "Séries",
        "Podcasts", "Gameplay", "Educação", "Vlogs", "Outros"
    ]

    var body: some View {
        GeometryReader { geo in
            if geo.size.width < 980 {
                // Janela estreita: uma coluna só, histórico embaixo
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        mainColumn
                        historyColumn
                    }
                    .padding(24)
                    .frame(maxWidth: 780)
                    .frame(maxWidth: .infinity)
                }
            } else {
                // Janela larga: as duas colunas formam um container único centralizado,
                // assim as margens externas ficam simétricas em qualquer largura
                HStack(alignment: .top, spacing: 28) {
                    ScrollView(showsIndicators: false) {
                        mainColumn
                            .padding(.vertical, 28)
                    }
                    .frame(maxWidth: 820)

                    ScrollView(showsIndicators: false) {
                        historyColumn
                            .padding(.vertical, 28)
                    }
                    .frame(width: min(460, max(340, geo.size.width * 0.32)))
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 1340)
                .frame(maxWidth: .infinity)
            }
        }
        .background(backgroundView)
        .onChange(of: url) { _, newValue in
            inspectURL(newValue)
        }
    }

    // MARK: - Columns

    private var mainColumn: some View {
        VStack(spacing: 14) {
            engineStatus
                .frame(maxWidth: .infinity, alignment: .trailing)

            if !manager.dependenciesReady {
                setupBanner
            }

            downloadCard

            // Progresso e conclusão ficam abaixo do card de download
            if manager.isDownloading || manager.progress > 0 {
                progressCard
            }

            if let item = manager.lastDownload, !manager.isDownloading {
                completionCard(item)
            }
        }
    }

    private var historyColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            historyHeader

            if !manager.history.isEmpty {
                historyGrid
            } else {
                emptyHistoryState
            }
        }
    }

    // MARK: - Auto-inspect

    private func inspectURL(_ raw: String) {
        inspectTask?.cancel()
        withAnimation(.spring(response: 0.3)) {
            videoInfo = nil
            inspectError = nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("http"), trimmed.count > 12 else {
            isInspecting = false
            return
        }
        inspectTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            isInspecting = true
            defer { isInspecting = false }
            do {
                let info = try await VideoInfoService.shared.fetch(url: trimmed)
                guard !Task.isCancelled else { return }
                applyInfo(info)
            } catch {
                // Alguns links (Instagram, restritos) precisam de cookies do navegador
                if let info = try? await VideoInfoService.shared.fetch(url: trimmed, cookieBrowser: detectDefaultBrowser()) {
                    guard !Task.isCancelled else { return }
                    applyInfo(info)
                } else if !Task.isCancelled {
                    withAnimation { inspectError = "Não foi possível analisar o link — o download ainda pode funcionar" }
                }
            }
        }
    }

    private var maxHeight: Int {
        videoInfo?.formats.filter { $0.kind != .audioOnly }.map(\.height).max() ?? 0
    }

    private var availableHeights: [Int] {
        guard let info = videoInfo else { return [] }
        return Set(info.formats.filter { $0.kind != .audioOnly }.map(\.height))
            .filter { $0 >= 144 }
            .sorted(by: >)
    }

    private func resLabel(_ h: Int) -> String {
        if h >= 2160 { return "4K" }
        if h >= 1440 { return "2K" }
        return "\(h)p"
    }

    // Se a qualidade selecionada não existe neste vídeo, volta para "Melhor"
    private func snapQualityToAvailable() {
        guard maxHeight > 0, !audioOnly,
              let required = ["2160p": 2160, "1440p": 1440, "1080p": 1080, "720p": 720, "480p": 480][quality],
              required > maxHeight else { return }
        quality = "best"
    }

    private func applyInfo(_ info: VideoInfo) {
        withAnimation(.spring(response: 0.35)) { videoInfo = info }
        manager.videoInfo = info
        snapQualityToAvailable()

        // Marca legendas automaticamente quando o vídeo tem legendas do canal
        if info.subtitleLangs.isEmpty {
            subtitles = false
        } else {
            subtitles = true
            let preferred = info.subtitleLangs.filter { $0.hasPrefix("pt") || $0.hasPrefix("en") }
            subLangs = (preferred.isEmpty ? Array(info.subtitleLangs.prefix(3)) : preferred)
                .joined(separator: ",")
        }
    }

    // Opções de qualidade: quando o vídeo foi analisado, só mostra o que existe de verdade
    private var qualityOptions: [(String, String)] {
        var opts: [(String, String)] = [(maxHeight > 0 ? "Melhor · \(resLabel(maxHeight))" : "Melhor", "best")]
        for (label, h) in [("4K", 2160), ("2K", 1440), ("1080p", 1080), ("720p", 720), ("480p", 480)] {
            if maxHeight == 0 || h <= maxHeight {
                opts.append((label, "\(h)p"))
            }
        }
        return opts
    }

    // MARK: - Preview Card

    private func previewCard(_ info: VideoInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail grande em 16:9 ocupando a largura do card — clique abre no navegador
            Button {
                if let u = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    NSWorkspace.shared.open(u)
                }
            } label: {
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay(thumbnail(for: info.thumbnail, fallbackIcon: "film", fallbackColor: .secondary))
                    .overlay(
                        Circle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                                    .offset(x: 2)
                            )
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if !info.durationFormatted.isEmpty {
                            Text(info.durationFormatted)
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                                .padding(10)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Assistir no navegador")

            // Linha compacta: título + indicador de legendas
            HStack(spacing: 8) {
                Text(info.title.isEmpty ? "Vídeo" : info.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if !info.subtitleLangs.isEmpty {
                    Label(info.subtitleLangs.prefix(3).joined(separator: ", "), systemImage: "captions.bubble.fill")
                        .font(.caption2)
                        .foregroundStyle(YT.red)
                        .help("Este vídeo tem legendas — a opção Legendas foi marcada automaticamente")
                }
            }
            .padding(.horizontal, 2)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var backgroundView: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [YT.red.opacity(0.04), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    // MARK: - Engine status (versão do yt-dlp)

    private var engineStatus: some View {
        HStack(spacing: 12) {
            if manager.isUpdatingYtdlp {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Atualizando motor…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
                .help("O yt-dlp (motor de download) está sendo atualizado para a versão mais recente")
            } else if let ver = manager.ytdlpVersion, !ver.isEmpty {
                Label("Motor \(ver)", systemImage: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                    .help("yt-dlp \(ver) — o motor que baixa os vídeos. Ele se atualiza automaticamente sempre que você abre o app.")
            }
        }
    }

    // MARK: - History Header & Grid

    private var historyHeader: some View {
        HStack {
            Text("Recentes")
                .font(.title2).fontWeight(.bold)
            Spacer()
            if !manager.history.isEmpty {
                Button {
                    manager.clearHistory()
                } label: {
                    Text("Limpar")
                        .font(.subheadline)
                        .foregroundStyle(YT.red)
                }
                .buttonStyle(.plain)
                .help("Limpar histórico")
            }
        }
    }

    private var historyGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 14)],
            spacing: 14
        ) {
            ForEach(manager.history) { item in
                historyCard(item)
            }
        }
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Nenhum download ainda")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Date Formatter (PT-BR)

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Download Card

    private var downloadCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            urlField

            if let error = inspectError {
                Label(error, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let info = videoInfo {
                previewCard(info)
            }

            VStack(alignment: .leading, spacing: 12) {
                optionRow(label: "Qualidade") {
                    SegmentedPills(
                        items: qualityOptions,
                        selection: $quality,
                        isActive: !audioOnly,
                        onSelect: { _ in audioOnly = false }
                    )
                    .opacity(audioOnly ? 0.45 : 1)
                }
                optionRow(label: "Formato") {
                    SegmentedPills(
                        items: [("MP4", "mp4"), ("WebM", "webm"), ("MKV", "mkv")],
                        selection: $format,
                        isActive: !audioOnly,
                        onSelect: { _ in audioOnly = false }
                    )

                    // MP3 fica separado: é "só áudio", não um formato de vídeo
                    Button {
                        withAnimation(.spring(response: 0.28)) { audioOnly = true; format = "mp3" }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "music.note")
                                .font(.system(size: 10, weight: .semibold))
                            Text("MP3 · só áudio")
                        }
                        .font(.system(size: 12, weight: audioOnly ? .semibold : .regular))
                        .foregroundStyle(audioOnly ? .white : .primary)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(Capsule().fill(audioOnly ? AnyShapeStyle(YT.gradient) : AnyShapeStyle(Color.primary.opacity(0.05))))
                        .padding(3)
                        .background(Capsule().fill(Color.primary.opacity(audioOnly ? 0.05 : 0)))
                    }
                    .buttonStyle(.plain)

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

            FocusableTextField(
                text: $url,
                placeholder: "Cole o link do vídeo aqui…",
                onCommit: startDownload,
                onFocusChange: { urlFocused = $0 }
            )

            if isInspecting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Analisando…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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

    // Controle segmentado com indicador vermelho que desliza entre as opções
    private struct SegmentedPills: View {
        let items: [(String, String)]
        @Binding var selection: String
        var isActive: Bool = true
        var onSelect: (String) -> Void = { _ in }
        @Namespace private var ns

        var body: some View {
            HStack(spacing: 2) {
                ForEach(items, id: \.1) { label, value in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            selection = value
                        }
                        onSelect(value)
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: selection == value && isActive ? .semibold : .regular))
                            .foregroundStyle(selection == value && isActive ? .white : .primary)
                            .padding(.horizontal, 13).padding(.vertical, 6)
                            .background {
                                if selection == value && isActive {
                                    Capsule()
                                        .fill(YT.gradient)
                                        .matchedGeometryEffect(id: "indicator", in: ns)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
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

    // MARK: - History Card

    private func historyCard(_ item: DownloadHistoryItem) -> some View {
        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.outputDir)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                ZStack(alignment: .bottomLeading) {
                    thumbnail(for: item.thumbnailURL, fallbackIcon: "film", fallbackColor: .secondary)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    
                    // Data overlay
                    Text(formatDate(item.timestamp))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                        .padding(8)
                }

                // Info section
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? "Download" : item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    HStack(spacing: 6) {
                        Text(item.category)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            withAnimation {
                                manager.history.removeAll { $0.id == item.id }
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.quaternary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Clique para abrir no Finder")
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
