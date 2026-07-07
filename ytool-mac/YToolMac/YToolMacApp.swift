import SwiftUI

@main
struct YToolMacApp: App {
    @StateObject private var downloadManager = DownloadManager()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(downloadManager)
                    .frame(minWidth: 760, minHeight: 560)
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showSplash = false
                    }
                }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 940, height: 720)
        .commands {
            // Garante que o menu Edit existe com Cmd+V funcional
            CommandGroup(after: .pasteboard) { }
        }
    }
}

struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.92, green: 0.20, blue: 0.18),
                                     Color(red: 0.72, green: 0.08, blue: 0.12)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: 92, height: 92)
                        .shadow(color: .red.opacity(0.3), radius: 16, y: 6)
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(appear ? 1 : 0.7)

                Text("YTool")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Download feito simples")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                appear = true
            }
        }
    }
}
