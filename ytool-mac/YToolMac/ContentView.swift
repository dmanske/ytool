import SwiftUI

enum SidebarTab: String, CaseIterable {
    case downloads = "Downloads"
    case subscriptions = "Inscrições"
    case playlists = "Playlists"
    case config = "Configurações"

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle.fill"
        case .subscriptions: return "person.2.fill"
        case .playlists: return "list.bullet.rectangle.portrait.fill"
        case .config: return "gearshape.fill"
        }
    }
    
    var gradient: LinearGradient {
        switch self {
        case .downloads: 
            return LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .subscriptions: 
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .playlists: 
            return LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .config: 
            return LinearGradient(colors: [.gray, .secondary.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: SidebarTab = .downloads
    @State private var isAppearing = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            ZStack {
                // Animated gradient background
                AnimatedGradientBackground(tab: selectedTab)
                
                // Content
                Group {
                    switch selectedTab {
                    case .downloads:
                        DownloadsView()
                    case .subscriptions:
                        PlaceholderView(
                            title: "Inscrições",
                            description: "Exporte, importe ou transfira inscrições entre contas do YouTube",
                            icon: "person.2.fill",
                            gradient: selectedTab.gradient
                        )
                    case .playlists:
                        PlaceholderView(
                            title: "Playlists",
                            description: "Copie playlists públicas e privadas entre contas do YouTube",
                            icon: "list.bullet.rectangle.portrait.fill",
                            gradient: selectedTab.gradient
                        )
                    case .config:
                        PlaceholderView(
                            title: "Configurações",
                            description: "Pasta de downloads, categorias e credenciais do Google",
                            icon: "gearshape.fill",
                            gradient: selectedTab.gradient
                        )
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAppearing = true
            }
        }
    }
}

struct AnimatedGradientBackground: View {
    let tab: SidebarTab
    
    var body: some View {
        tab.gradient
            .opacity(0.03)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: tab)
    }
}

struct SidebarView: View {
    @Binding var selectedTab: SidebarTab
    @State private var hoveredTab: SidebarTab?

    var body: some View {
        List(SidebarTab.allCases, id: \.self, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
                .badge(tab == .downloads ? "Novo" : "")
                .listItemTint(tab == selectedTab ? .red : .accentColor)
        }
        .navigationTitle("YTool")
        .listStyle(.sidebar)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
    }
}

struct PlaceholderView: View {
    let title: String
    let description: String
    let icon: String
    let gradient: LinearGradient
    
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(gradient)
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1.1 : 0.9)
                    .opacity(0.2)
                
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(gradient)
                    .symbolEffect(.bounce, value: isAnimating)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text("Em breve")
                        .font(.callout)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(gradient, lineWidth: 1.5)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isAnimating ? 1 : 0)
        .offset(y: isAnimating ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
    }
}
