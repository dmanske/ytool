# YTool for macOS

App nativo macOS (SwiftUI) moderno para download de vídeos do YouTube e Instagram.

## ✨ Recursos Modernos

- 🎨 **Design Responsivo** - Layout adaptável que funciona em diferentes tamanhos de janela
- 🌊 **Animações Fluidas** - Transições suaves e animações de entrada elegantes
- 🎭 **Splash Screen** - Animação de boas-vindas ao iniciar o app
- 🎯 **UI Moderna** - Cards com glassmorphism, gradientes e efeitos visuais
- ⚡ **Feedback Visual** - Indicadores de progresso circulares e lineares
- 🖱️ **Interações Intuitivas** - Hover effects e animações de escala
- 🎨 **Gradientes Animados** - Fundo sutil que muda conforme a aba selecionada

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
    ├── YToolMacApp.swift      # Entry point com splash screen
    ├── ContentView.swift      # Sidebar + navegação com animações
    ├── DownloadsView.swift    # Tela de downloads moderna e responsiva
    └── DownloadManager.swift  # Lógica de download via yt-dlp subprocess
```

## 🎨 Melhorias de Design

### Layout Responsivo
- **Modo Regular** (janela grande): Split view com formulário à esquerda e histórico à direita
- **Modo Compacto** (janela pequena): Layout vertical empilhado com scroll

### Animações
- **Splash Screen**: Animação de entrada com logo rotativo e gradiente
- **Entrada de Elementos**: Cada seção aparece com fade-in e slide suave
- **Transições de Aba**: Mudanças suaves entre Downloads, Inscrições, Playlists e Configurações
- **Progresso**: Indicador circular e linear com animações fluidas
- **Hover Effects**: Cards e botões respondem ao mouse

### Componentes Modernos
- **ModernPicker**: Cards com ícones e glassmorphism
- **ModernProgressCard**: Indicador de progresso com círculo e barra
- **ModernHistoryRow**: Lista de downloads com ícones de plataforma e hover
- **AnimatedGradientBackground**: Fundo gradiente que muda por aba

## Status

- [x] Estrutura do app com sidebar
- [x] Tela de downloads funcional
- [x] Download via yt-dlp subprocess
- [x] Progresso em tempo real
- [x] Histórico de downloads
- [x] Abrir pasta no Finder
- [x] Cancelar download
- [x] **Layout responsivo**
- [x] **Animações de entrada**
- [x] **Splash screen**
- [x] **Design moderno com glassmorphism**
- [x] **Gradientes animados**
- [x] **Hover effects**
- [ ] Inscrições YouTube (OAuth)
- [ ] Playlists YouTube
- [ ] Configurações
- [ ] Dark mode personalizado
## 🚀 Próximos Passos

1. Implementar OAuth para YouTube API
2. Adicionar tela de configurações funcional
3. Suporte a temas personalizados
4. Preview de vídeo antes do download
5. Download em lote de playlists

