import SwiftUI

enum SidebarTab: String, CaseIterable {
    case downloads = "Downloads"
    case subscriptions = "Inscrições"
    case playlists = "Playlists"
    case config = "Configurações"

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle"
        case .subscriptions: return "person.2"
        case .playlists: return "list.bullet.rectangle"
        case .config: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: SidebarTab = .downloads

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            switch selectedTab {
            case .downloads:
                DownloadsView()
            case .subscriptions:
                PlaceholderView(title: "Inscrições", description: "Exporte, importe ou transfira inscrições entre contas do YouTube", icon: "person.2")
            case .playlists:
                PlaceholderView(title: "Playlists", description: "Copie playlists públicas e privadas entre contas do YouTube", icon: "list.bullet.rectangle")
            case .config:
                PlaceholderView(title: "Configurações", description: "Pasta de downloads, categorias e credenciais do Google", icon: "gearshape")
            }
        }
    }
}

struct SidebarView: View {
    @Binding var selectedTab: SidebarTab

    var body: some View {
        List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
        }
        .navigationTitle("YTool")
        .listStyle(.sidebar)
    }
}

struct PlaceholderView: View {
    let title: String
    let description: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title)
                .fontWeight(.semibold)
            Text(description)
                .foregroundStyle(.secondary)
            Text("Em breve")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
