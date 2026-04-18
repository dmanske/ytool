import SwiftUI

// MARK: - Main View

struct DownloadsView: View {
    @EnvironmentObject private var manager: DownloadManager

    // Form state
    @State private var url = ""
    @State private var quality = "best"
    @State private var format = "mp4"
    @State private var audioOnly = false
    @State private var category = "Música"
    @State private var customFilename = ""
    @State private var subtitles = false
    @State private var subLangs = "en,pt"

    // UI state
    @State private var isInspecting = false
    @State private var inspectError: String?
    @State private var selectedFormatID: String?
    @State private var showFormats = false
    @State private var showAdvanced = false
    @State private var isAnimating = false
    @FocusState private var urlFocused: Bool

    private let qualities   = ["best", "1080p", "720p", "480p", "360p"]
    private let formats     = ["mp4", "webm", "mkv"]
    private let categories  = ["Música", "Tutoriais", "Filmes", "Outros"]

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 800 {
                HSplitView {
                    formColumn.frame(minWidth: 480, idealWidth: 620)
                    historyColumn.frame(minWidth: 280, idealWidth: 360)
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        formColumn
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { urlFocused = true }
        }
        // Auto-inspect when URL changes and looks valid
        .onChange(of: url) { _, newValue in
            inspectError = nil
            if newValue.isEmpty {
                manager.videoInfo = nil
                selectedFormatID = nil
                showFormats = false
            }
        }
    }

    // MARK: - Form column

    private var formColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                urlSection
                if manager.videoInfo != nil { videoPreview }
                if showFormats && !(manager.videoInfo?.formats.isEmpty ?? true) { formatsSection }
                optionsGrid
                advancedSection
                actionButtons
                if manager.isDownloading || manager.progress > 0 { progressCard }
                if !manager.queue.isEmpty { queueSection }
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
                Text("Baixe vídeos e áudios do YouTube e Instagram")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : -16)
    }

    // MARK: - URL section

    private var urlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("URL do Vídeo", systemImage: "link")
                .font(.headline)

            HStack(spacing: 10) {
                TextField("Cole a URL do YouTube ou Instagram aqui...", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .focused($urlFocused)
                    .onSubmit { triggerInspect() }

                if !url.isEmpty {
                    Button {
                        clearURL()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                Button {
                    triggerInspect()
                } label: {
                    if isInspecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Inspecionar", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(url.isEmpty || isInspecting)
            }

            // Platform tags
            HStack(spacing: 8) {
                PlatformTag(name: "YouTube",  color: .red,  active: url.contains("youtube") || url.contains("youtu.be"))
                PlatformTag(name: "Instagram", color: .pink, active: url.contains("instagram"))
                Spacer()
                if let err = inspectError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 16)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.15), value: isAnimating)
    }

    // MARK: - Video preview

    private var videoPreview: some View {
        Group {
            if let info = manager.videoInfo {
                HStack(spacing: 14) {
                    // Thumbnail
                    AsyncImage(url: URL(string: info.thumbnail)) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(info.title)
                            .font(.subheadline).fontWeight(.semibold)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            if !info.uploader.isEmpty {
                                Label(info.uploader, systemImage: "person.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if info.duration > 0 {
                                Label(info.durationFormatted, systemImage: "clock")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            withAnimation(.spring(response: 0.3)) { showFormats.toggle() }
                        } label: {
                            Label(showFormats ? "Ocultar formatos" : "Ver formatos disponíveis",
                                  systemImage: showFormats ? "chevron.up" : "chevron.down")
                                .font(.caption).fontWeight(.medium)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
    }

    // MARK: - Formats section

    private var formatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FORMATOS DISPONÍVEIS")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(manager.videoInfo?.formats ?? []) { fmt in
                        FormatRow(format: fmt, isSelected: selectedFormatID == fmt.id) {
                            selectedFormatID = selectedFormatID == fmt.id ? nil : fmt.id
                        }
                    }
                }
            }
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))

            if selectedFormatID != nil {
                Text("Formato específico selecionado — as opções de Qualidade/Formato abaixo serão ignoradas.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - Options grid

    private var optionsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                OptionCard(title: "Qualidade", icon: "sparkles", selection: $quality, options: qualities)
                OptionCard(title: "Formato",   icon: "film",     selection: $format,  options: formats)
            }
            HStack(spacing: 12) {
                OptionCard(title: "Categoria", icon: "folder", selection: $category, options: categories)
                AudioToggleCard(audioOnly: $audioOnly)
            }
        }
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 16)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.25), value: isAnimating)
    }

    // MARK: - Advanced section (nome, legendas)

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                // Custom filename
                VStack(alignment: .leading, spacing: 6) {
                    Label("Nome do arquivo (opcional)", systemImage: "pencil")
                        .font(.subheadline).fontWeight(.medium)
                    TextField("Deixe vazio para usar o título do vídeo", text: $customFilename)
                        .textFieldStyle(.roundedBorder)
                }

                // Subtitles
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $subtitles) {
                        Label("Baixar legendas", systemImage: "captions.bubble")
                            .font(.subheadline).fontWeight(.medium)
                    }
                    .toggleStyle(.switch).tint(.red)

                    if subtitles {
                        HStack(spacing: 8) {
                            Text("Idiomas:")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("en,pt,es", text: $subLangs)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)
                            Text("separados por vírgula")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Opções avançadas", systemImage: "slider.horizontal.3")
                .font(.subheadline).fontWeight(.medium)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                startDownload()
            } label: {
                Label("Baixar", systemImage: "arrow.down.circle.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(url.isEmpty || manager.isDownloading)
            .keyboardShortcut(.return, modifiers: .command)

            Button {
                addToQueue()
            } label: {
                Label("Fila", systemImage: "list.bullet.rectangle.portrait")
                    .fontWeight(.medium)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(url.isEmpty)
            .help("Adicionar à fila de downloads")

            if manager.isDownloading {
                Button {
                    manager.cancel()
                } label: {
                    Label("Cancelar", systemImage: "xmark.circle.fill")
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 16)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.35), value: isAnimating)
    }

    // MARK: - Progress card

    private var progressCard: some View {
        ModernProgressCard(manager: manager)
            .transition(.scale(scale: 0.97).combined(with: .opacity))
    }

    // MARK: - Queue section

    private var queueSection: some View {
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
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .disabled(manager.isProcessingQueue || manager.isDownloading)
            }

            ForEach(manager.queue) { item in
                QueueRow(item: item) {
                    manager.removeFromQueue(id: item.id)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
        .transition(.scale(scale: 0.97).combined(with: .opacity))
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
                        Label("Limpar", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if manager.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
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
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(.background)
    }

    // MARK: - Actions

    private func triggerInspect() {
        guard !url.isEmpty, !isInspecting else { return }
        isInspecting = true
        inspectError = nil
        manager.videoInfo = nil
        selectedFormatID = nil

        Task {
            do {
                let info = try await VideoInfoService.shared.fetch(url: url)
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
            manager.videoInfo = nil
            selectedFormatID = nil
            showFormats = false
        }
    }
}

// MARK: - Subviews

struct PlatformTag: View {
    let name: String
    let color: Color
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(active ? color : .secondary).frame(width: 6, height: 6)
            Text(name).font(.caption2).fontWeight(.medium)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(active ? color.opacity(0.12) : Color.secondary.opacity(0.08))
        .clipShape(Capsule())
        .animation(.spring(response: 0.3), value: active)
    }
}

struct FormatRow: View {
    let format: VideoFormat
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text(format.kind.emoji).font(.body)
                Text(format.label)
                    .font(.caption).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(format.kind.rawValue)
                    .font(.caption2).foregroundStyle(.secondary)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(isSelected ? Color.red.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct OptionCard: View {
    let title: String
    let icon: String
    @Binding var selection: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
    }
}

struct AudioToggleCard: View {
    @Binding var audioOnly: Bool

    var body: some View {
        HStack {
            Image(systemName: audioOnly ? "music.note" : "video")
                .font(.title3)
                .foregroundStyle(audioOnly ? .red : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apenas Áudio").font(.subheadline).fontWeight(.medium)
                Text("MP3").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $audioOnly).labelsHidden().toggleStyle(.switch).tint(.red)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(audioOnly ? AnyShapeStyle(Color.red.opacity(0.3)) : AnyShapeStyle(Color.quaternary), lineWidth: 1.5)
        )
        .animation(.spring(response: 0.3), value: audioOnly)
    }
}

struct ModernProgressCard: View {
    @ObservedObject var manager: DownloadManager
    @State private var showLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.statusText)
                        .font(.headline).fontWeight(.semibold)
                    if let last = manager.logLines.last {
                        Text(last).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).monospaced()
                    }
                }
                Spacer()
                // Circular progress
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
                    Text("\(Int(manager.progress))%")
                        .font(.caption2).fontWeight(.bold).monospacedDigit()
                }
            }

            // Linear bar
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

            // Log toggle
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

    var statusLabel: String {
        switch item.status {
        case .pending: return "Pendente"
        case .active:  return "Baixando"
        case .done:    return "Concluído"
        case .error:   return "Erro"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(item.url).font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(statusLabel).font(.caption2).foregroundStyle(statusColor)
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

    var platformIcon: String {
        if item.url.contains("youtube") || item.url.contains("youtu.be") { return "play.rectangle.fill" }
        if item.url.contains("instagram") { return "camera.fill" }
        return "globe"
    }

    var platformColor: Color {
        if item.url.contains("youtube") || item.url.contains("youtu.be") { return .red }
        if item.url.contains("instagram") { return .pink }
        return .blue
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
