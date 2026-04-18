# YTool for macOS

App nativo macOS (SwiftUI) para download de vídeos do YouTube e Instagram.

## Requisitos

- macOS 14 (Sonoma) ou superior
- Xcode 15.4+
- yt-dlp instalado (`brew install yt-dlp`)
- ffmpeg instalado (`brew install ffmpeg`)

## Como abrir

```bash
# Mova pra pasta de projetos
mv ytool-mac ~/Documents/Projects/YToolMac

# Abra no Xcode
cd ~/Documents/Projects/YToolMac
open Package.swift
```

O Xcode vai abrir o projeto como Swift Package. Clique ▶️ pra rodar.

## Estrutura

```
YToolMac/
├── Package.swift              # Swift Package Manager config
└── YToolMac/
    ├── YToolMacApp.swift      # Entry point (@main)
    ├── ContentView.swift      # Sidebar + navegação entre abas
    ├── DownloadsView.swift    # Tela de downloads (formulário + histórico)
    └── DownloadManager.swift  # Lógica de download via yt-dlp subprocess
```

## Status

- [x] Estrutura do app com sidebar
- [x] Tela de downloads funcional
- [x] Download via yt-dlp subprocess
- [x] Progresso em tempo real
- [x] Histórico de downloads
- [x] Abrir pasta no Finder
- [x] Cancelar download
- [ ] Inscrições YouTube (OAuth)
- [ ] Playlists YouTube
- [ ] Configurações
- [ ] Tema claro/escuro automático (segue sistema)
