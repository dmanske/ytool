import SwiftUI

// MARK: - Platform

enum Platform: String, CaseIterable {
    case youtube  = "YouTube"
    case instagram = "Instagram"

    var color: Color {
        switch self {
        case .youtube:  return .red
        case .instagram: return .pink
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .youtube:
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .instagram:
            return LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var icon: String {
        switch self {
        case .youtube:  return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        }
    }

    var placeholder: String {
        switch self {
        case .youtube:  return "https://youtube.com/watch?v=..."
        case .instagram: return "https://instagram.com/p/..."
        }
    }

    var note: String {
        switch self {
        case .youtube:  return "Vídeos, Shorts e playlists públicas"
        case .instagram: return "Posts, Reels e Stories públicos"
        }
    }

    func matches(_ url: String) -> Bool {
        switch self {
        case .youtube:  return url.contains("youtube.com") || url.contains("youtu.be")
        case .instagram: return url.contains("instagram.com")
        }
    }
}

// MARK: - Main View

struct DownloadsView: View {
    @EnvironmentObject private var manager: DownloadManager
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 900 {
                HSplitView {
                    mainColumn(wide: true).frame(minWidth: 560, idealWidth: 700)
                    historyColumn.frame(minWidth: 280, idealWidth: 360)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        mainColumn(wide: false)
                        Divider()
                        historyColumn.frame(height: 380)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Main column

    private func mainColumn(wide: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                // Two platform cards side by side
                if wide {
                    HStack(alignment: .top, spacing: 16) {
                        PlatformDownloadCard(platform: .youtube)
                        PlatformDownloadCard(platform: .instagram)
                    }
                } else {
                    VStack(spacing: 16) {
                        PlatformDownloadCard(platform: .youtube)
                        PlatformDownloadCard(platform: .instagram)
                    }
                }

                if manager.isDownloading || manager.progress > 0 {
                    ModernProgressCard(manager: manager)
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                }

                if !manager.queue.isEmpty {
                    QueueSection()
                }
            }
            .padding(28)
        }
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: isAnimating)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Bem-vindo ao YTool")
                    .font(.title2).fontWeight(.bold)
                Text("Escolha a plataforma e cole a URL para baixar")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : -16)
    }

    // MARK: - History column

    private var historyColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Downloads Recentes", systemImage: "clock.fill")
                    .font(.headline)
                Spacer()
                if !manager.history.isEmpty {
                    Button {
                        withAnimation { manager.clearHistory() }
                    } label: {
                        Label("Limpar", systemImage: "trash").font(.caption)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20)

            if manager.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36)).foregroundStyle(.quaternary)
                    Text("Nenhum download ainda")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(manager.history) { item in
                            HistoryItemRow(item: item)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 12)
                }
            }
        }
        .background(.background)
    }
}

// MARK: - Platform Download Card

struct PlatformDownloadCard: View {
    let platform: Platform
    @EnvironmentObject private var manager: DownloadManager

    @State private var url = ""
    @State private var quality = "best"
    @State private var format = "mp4"
    @State private var audioOnly = false
    @State private var category = "Música"
    @State private var customFilename = ""
    @State private var subtitles = false
    @State private var subLangs = "en,pt"

    @State private var isInspecting = false
    @State private var inspectError: String?
    @State private var videoInfo: VideoInfo?
    @State private var selectedFormatID: String?
    @State private var showFormats = false
    @State private var showAdvanced = false
    @State private var isAnimating = false
    @FocusState private var urlFocused: Bool

    private let qualities  = ["best", "1080p", "720p", "480p", "360p"]
    private let formats    = ["mp4", "webm", "mkv"]
    private let categories = ["Música", "Tutoriais", "Filmes", "Outros"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardHeader
            Divider().overlay(platform.color.opacity(0.2))
            cardBody
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(platform.color.opacity(0.25), lineWidth: 1.5)
        )
        .shadow(color: platform.color.opacity(0.06), radius: 12, y: 4)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(platform == .youtube ? 0.15 : 0.25)) {
                isAnimating = true
            }
        }
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
        .onChange(of: url) { _, newValue in
            inspectError = nil
            if newValue.isEmpty {
                videoInfo = nil
                selectedFormatID = nil
                showFormats = false
            }
        }
    }

    // MARK: Card header

    private var cardHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(platform.gradient)
                    .frame(width: 36, height: 36)
                Image(systemName: platform.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(platform.rawValue)
                    .font(.headline).fontWeight(.bold)
                Text(platform.note)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(platform.color.opacity(0.04))
    }

    // MARK: Card body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            // URL field
            HStack(spacing: 8) {
                TextField(platform.placeholder, text: $url)
                    .textFieldStyle(.roundedBorder)
                    .focused($urlFocused)
                    .onSubmit { triggerInspect() }

                if !url.isEmpty {
                    Button { clearURL() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                Button { triggerInspect() } label: {
                    if isInspecting {
                        ProgressView().controlSize(.small).frame(width: 20)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .tint(platform.color)
                .disabled(url.isEmpty || isInspecting)
                .help("Inspecionar formatos")
            }

            if let err = inspectError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .transition(.opacity)
            }

            // Video preview
            if let info = videoInfo {
                videoPreview(info: info)
            }

            // Formats
            if showFormats, let formats = videoInfo?.formats, !formats.isEmpty {
                formatsSection(formats: formats)
            }

            // Options row
            HStack(spacing: 10) {
                Picker("", selection: $quality) {
                    ForEach(qualities, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity)
                .help("Qualidade")

                if !audioOnly {
                    Picker("", selection: $format) {
                        ForEach(formats, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity)
                    .help("Formato")
                }

                Picker("", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(maxWidth: .infinity)
                .help("Categoria")

                Toggle("", isOn: $audioOnly)
                    .toggleStyle(.switch).tint(platform.color).labelsHidden()
                    .help("Somente áudio (MP3)")
            }

            // Advanced options
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Nome do arquivo (opcional)", text: $customFilename)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        Toggle(isOn: $subtitles) {
                            Text("Legendas").font(.caption)
                        }
                        .toggleStyle(.switch).tint(platform.color)

                        if subtitles {
                            TextField("en,pt", text: $subLangs)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Avançado", systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    startDownload()
                } label: {
                    Label("Baixar", systemImage: "arrow.down.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(platform.color)
                .disabled(url.isEmpty || manager.isDownloading)
                .keyboardShortcut(platform == .youtube ? .return : "i", modifiers: .command)

                Button {
                    addToQueue()
                } label: {
                    Image(systemName: "list.bullet.rectangle.portrait")
                }
                .buttonStyle(.bordered)
                .tint(platform.color)
                .disabled(url.isEmpty)
                .help("Adicionar à fila")
            }
        }
        .padding(16)
    }

    // MARK: Video preview

    private func videoPreview(info: VideoInfo) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: info.thumbnail)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 90, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(info.title).font(.caption).fontWeight(.semibold).lineLimit(2)
                HStack(spacing: 6) {
                    if !info.uploader.isEmpty {
                        Text(info.uploader).font(.caption2).foregroundStyle(.secondary)
                    }
                    if info.duration > 0 {
                        Text(info.durationFormatted).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button {
                    withAnimation(.spring(response: 0.3)) { showFormats.toggle() }
                } label: {
                    Label(showFormats ? "Ocultar formatos" : "Ver formatos",
                          systemImage: showFormats ? "chevron.up" : "chevron.down")
                        .font(.caption2).fontWeight(.medium)
                }
                .buttonStyle(.borderless).foregroundStyle(platform.color)
            }
        }
        .padding(10)
        .background(platform.color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(platform.color.opacity(0.15), lineWidth: 1))
        .transition(.scale(scale: 0.97).combined(with: .opacity))
    }

    // MARK: Formats section

    private func formatsSection(formats: [VideoFormat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FORMATOS").font(.caption2).fontWeight(.semibold).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(formats) { fmt in
                        Button {
                            selectedFormatID = selectedFormatID == fmt.id ? nil : fmt.id
                        } label: {
                            HStack(spacing: 8) {
                                Text(fmt.kind.emoji)
                                Text(fmt.label).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                if selectedFormatID == fmt.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(platform.color)
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(selectedFormatID == fmt.id ? platform.color.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: Actions

    private func triggerInspect() {
        guard !url.isEmpty, !isInspecting else { return }
        isInspecting = true
        inspectError = nil
        videoInfo = nil
        selectedFormatID = nil

        Task {
            do {
                let info = try await VideoInfoService.shared.fetch(url: url)
                videoInfo = info
                manager.videoInfo = info
                if !info.formats.isEmpty { showFormats = true }
            } catch {
                inspectError = error.localizedDescription
            }
            isInspecting = false
        }
    }

    private func clearURL() {
        withAnimation(.spring(response: 0.3)) {
            url = ""
            videoInfo = nil
            manager.videoInfo = nil
            selectedFormatID = nil
            showFormats = false
            inspectError = nil
            urlFocused = true
        }
    }

    private func startDownload() {
        manager.download(
            url: url, quality: quality, format: format,
            audioOnly: audioOnly, category: category,
            customFilename: customFilename,
            subtitles: subtitles, subLangs: subLangs
        )
    }

    private func addToQueue() {
        manager.addToQueue(
            url: url, quality: quality, format: format,
            audioOnly: audioOnly, category: category,
            customFilename: customFilename,
            subtitles: subtitles, subLangs: subLangs
        )
        withAnimation(.spring(response: 0.3)) {
            url = ""
            videoInfo = nil
            selectedFormatID = nil
            showFormats = false
        }
    }
}

// MARK: - Queue Section

struct QueueSection: View {
    @EnvironmentObject private var manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Fila (\(manager.queue.count))", systemImage: "list.bullet.rectangle.portrait")
                    .font(.headline)
                Spacer()
                Button {
                    manager.startQueue()
                } label: {
                    Label("Iniciar fila", systemImage: "play.fill")
                        .font(.caption).fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                .disabled(manager.isProcessingQueue || manager.isDownloading)
            }
            ForEach(manager.queue) { item in
                QueueRow(item: item) { manager.removeFromQueue(id: item.id) }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
        .transition(.scale(scale: 0.97).combined(with: .opacity))
    }
}

// MARK: - Shared subviews (used by both cards and history)

struct ModernProgressCard: View {
    @ObservedObject var manager: DownloadManager
    @State private var showLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.statusText).font(.headline).fontWeight(.semibold)
                    if let last = manager.logLines.last {
                        Text(last).font(.caption2).foregroundStyle(.secondary).lineLimit(1).monospaced()
                    }
                }
                Spacer()
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 3).frame(width: 48, height: 48)
                    Circle()
                        .trim(from: 0, to: manager.progress / 100)
                        .stroke(
                            LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 48, height: 48)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.5), value: manager.progress)
                    Text("\(Int(manager.progress))%").font(.caption2).fontWeight(.bold).monospacedDigit()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.3)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (manager.progress / 100), height: 6)
                        .animation(.spring(response: 0.5), value: manager.progress)
                }
            }
            .frame(height: 6)

            if !manager.logLines.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3)) { showLogs.toggle() }
                } label: {
                    Label(showLogs ? "Ocultar log" : "Ver log",
                          systemImage: showLogs ? "chevron.up" : "terminal")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if showLogs {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(manager.logLines.suffix(15), id: \.self) { line in
                                Text(line).font(.caption2).foregroundStyle(.secondary).monospaced()
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                    .padding(8)
                    .background(.quaternary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    LinearGradient(colors: [.red.opacity(0.3), .orange.opacity(0.3)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .red.opacity(0.08), radius: 16, y: 8)
    }
}

struct QueueRow: View {
    let item: QueueItem
    let onRemove: () -> Void

    var statusColor: Color {
        switch item.status {
        case .pending: return .secondary
        case .active:  return .orange
        case .done:    return .green
        case .error:   return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(item.url).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(item.status == .pending ? "Pendente" : item.status == .active ? "Baixando" : item.status == .done ? "Concluído" : "Erro")
                .font(.caption2).foregroundStyle(statusColor)
            if item.status == .pending {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.quaternary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HistoryItemRow: View {
    let item: DownloadHistoryItem
    @State private var isHovered = false

    var platformColor: Color {
        if item.url.contains("youtube") || item.url.contains("youtu.be") { return .red }
        if item.url.contains("instagram") { return .pink }
        return .blue
    }

    var platformIcon: String {
        if item.url.contains("youtube") || item.url.contains("youtu.be") { return "play.rectangle.fill" }
        if item.url.contains("instagram") { return "camera.fill" }
        return "globe"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(platformColor.opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: platformIcon)
                    .font(.system(size: 17))
                    .foregroundStyle(platformColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? (URL(string: item.url)?.host ?? item.url) : item.title)
                    .font(.subheadline).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 6) {
                    Label(item.category, systemImage: "folder.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("·").font(.caption2).foregroundStyle(.tertiary)
                    Text(item.timestamp, style: .relative)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if isHovered {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.outputDir)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(10)
        .background(isHovered ? AnyShapeStyle(Color.quaternary.opacity(0.25)) : AnyShapeStyle(Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onHover { withAnimation(.spring(response: 0.25)) { isHovered = $0 } }
        .onTapGesture {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: item.outputDir)
        }
    }
}
