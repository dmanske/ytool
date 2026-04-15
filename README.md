# YTool

Aplicação web local para download de vídeos/áudios do YouTube e Instagram, e gerenciamento de inscrições e playlists entre contas do YouTube.

![Python 3.12+](https://img.shields.io/badge/Python-3.12+-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)
![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey)

## Funcionalidades

### Downloads
- Baixa vídeos e áudios do **YouTube** e **Instagram** (conteúdo público)
- **Auto-inspecionar** — cola a URL e os formatos são buscados automaticamente
- **Player do YouTube embutido** — prévia do vídeo direto no app
- **Cortar trecho** — defina início e fim pra baixar apenas uma parte do vídeo
- **Fila de downloads** — adicione várias URLs e baixe em sequência
- **Cancelar download** em andamento a qualquer momento
- **Nome personalizado** do arquivo antes de baixar
- **Arrastar e soltar** URL do navegador direto no campo
- **Auto-paste** do clipboard ao focar no campo de URL
- Seleção de qualidade (4K, 1080p, 720p, 480p, 360p), formato (mp4, webm, mkv) e categoria
- Modo somente áudio (extrai MP3)
- Download de legendas com seleção de idiomas
- Progresso em tempo real com velocidade, ETA e tamanho do arquivo
- **Histórico persistente** com thumbnails — salvo entre sessões
- Clique no histórico pra **abrir a pasta** no gerenciador de arquivos
- Botão de **limpar** URL/prévia e histórico
- Notificação nativa ao concluir
- Organização automática por plataforma e categoria

### Inscrições YouTube
- **Exportar** inscrições de uma conta para JSON/CSV
- **Importar** inscrições de um arquivo para outra conta
- **Transferir** inscrições diretamente entre duas contas
- Seleção de conta com tela de escolha (não precisa de dois navegadores)
- Progresso em tempo real com rate limiting automático (~1 req/s)

### Playlists YouTube
- Listar todas as playlists (públicas e privadas) de uma conta
- Copiar playlists selecionadas entre contas com checkbox
- Preserva privacidade (playlists privadas são recriadas como privadas)
- Progresso detalhado por playlist e por vídeo

### Interface
- **Tema escuro e claro** com toggle na sidebar
- Sidebar lateral de navegação com 4 seções
- Layout otimizado para telas grandes (27"+)
- Interface 100% em português brasileiro
- Modal de ajuda com guia completo
- Ícones do YouTube e Instagram que acendem ao detectar a plataforma

## Requisitos

- **Python 3.12+**
- **uv** (gerenciador de pacotes) — [instalação](https://docs.astral.sh/uv/getting-started/installation/)
- **yt-dlp** (instalado automaticamente via dependências)
- **ffmpeg** (necessário para merge de áudio/vídeo)

## Instalação

### macOS

```bash
# Instalar ffmpeg (se não tiver)
brew install ffmpeg

# Clonar e configurar
git clone https://github.com/dmanske/ytool.git
cd ytool
uv sync
cp .env.example .env
```

### Windows

```powershell
# 1. Instalar Python 3.12+ (se não tiver)
# Baixe em https://www.python.org/downloads/ — marque "Add to PATH"

# 2. Instalar uv
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# 3. Instalar ffmpeg via winget (ou baixe em https://ffmpeg.org/download.html)
winget install Gyan.FFmpeg

# 4. Clonar e configurar
git clone https://github.com/dmanske/ytool.git
cd ytool
uv sync
copy .env.example .env
```

### Linux

```bash
# Instalar ffmpeg (Ubuntu/Debian)
sudo apt install ffmpeg

# Clonar e configurar
git clone https://github.com/dmanske/ytool.git
cd ytool
uv sync
cp .env.example .env
```

## Uso

### macOS / Linux — Terminal
```bash
uv run python app.py
```
O app abre automaticamente em `http://localhost:8000`.

### macOS — Duplo clique
Dê duplo clique no arquivo `YTool.command`. Ele mata processos antigos, instala dependências e inicia o servidor automaticamente.

### Windows — Terminal
```powershell
uv run python app.py
```

### Windows — Duplo clique
Crie um arquivo `YTool.bat` na pasta do projeto com o conteúdo:

```bat
@echo off
cd /d "%~dp0"
uv sync --quiet
uv run python app.py
```

Dê duplo clique no `YTool.bat` pra iniciar.

## Configuração

### Variáveis de ambiente (.env)

```env
GOOGLE_CLIENT_ID=        # Necessário para Inscrições e Playlists
GOOGLE_CLIENT_SECRET=    # Necessário para Inscrições e Playlists
BASE_DOWNLOAD_DIR=~/Downloads/YTool
```

> No Windows, use um caminho como `C:\Users\SeuNome\Downloads\YTool`.

### Google OAuth (opcional)

Necessário apenas para os módulos de Inscrições e Playlists:

1. Acesse [Google Cloud Console](https://console.cloud.google.com/)
2. Crie um projeto e ative a **YouTube Data API v3**
3. Em **Credentials**, crie um **OAuth 2.0 Client ID** (tipo Web Application)
4. Adicione `http://localhost:8000/api/subscriptions/oauth/callback` como URI de redirecionamento
5. Copie o Client ID e Client Secret para o arquivo `.env`

> Você cria as credenciais **uma vez só**, em qualquer conta Google. Depois, conecta as duas contas do YouTube pelo app.

## Stack

| Componente | Tecnologia |
|-----------|-----------|
| Backend | Python 3.12+, FastAPI, uvicorn |
| Downloads | yt-dlp via asyncio subprocess |
| Auth | google-auth-oauthlib, google-api-python-client |
| Frontend | HTML/CSS/JS vanilla + Tailwind CSS (CDN) + Lucide Icons |
| Player | YouTube IFrame API |
| Progresso | Server-Sent Events (SSE) |
| Dependências | uv + pyproject.toml |

## Estrutura do Projeto

```
ytool/
├── app.py                  # Entry point — FastAPI app + lifespan
├── config.py               # Settings via pydantic-settings
├── pyproject.toml           # Dependências e metadata
├── YTool.command            # Launcher macOS (duplo clique)
├── routers/
│   ├── downloader.py        # Endpoints de download, cancelamento e histórico
│   ├── subscriptions.py     # Endpoints de inscrições e playlists
│   └── config.py            # Endpoints de configuração e abrir pasta
├── services/
│   ├── ytdlp_service.py     # Lógica de download via yt-dlp (com trim e cancel)
│   ├── youtube_auth.py      # OAuth + operações YouTube API (subs + playlists)
│   └── history_service.py   # Histórico persistente de downloads
└── static/
    ├── index.html           # SPA com 4 abas + modal de ajuda + player YouTube
    ├── app.js               # Lógica do frontend (fila, drag-drop, player, tema)
    └── style.css            # Estilos + tema claro/escuro
```

## API

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/formats?url=` | Inspeciona formatos disponíveis |
| `GET` | `/api/thumbnail?url=` | Proxy de thumbnail (evita CORS) |
| `GET` | `/api/history` | Histórico persistente de downloads |
| `DELETE` | `/api/history` | Limpa o histórico |
| `POST` | `/api/download` | Inicia download (SSE) |
| `POST` | `/api/download/cancel` | Cancela download em andamento |
| `GET` | `/api/subscriptions/export` | Exporta inscrições (JSON/CSV) |
| `POST` | `/api/subscriptions/import` | Importa inscrições de arquivo (SSE) |
| `POST` | `/api/subscriptions/transfer` | Transfere inscrições entre contas (SSE) |
| `GET` | `/api/subscriptions/playlists` | Lista playlists da conta |
| `POST` | `/api/subscriptions/playlists/transfer` | Copia playlists entre contas (SSE) |
| `GET` | `/api/config` | Retorna configurações atuais |
| `POST` | `/api/config` | Salva configurações |
| `POST` | `/api/config/open-folder` | Abre pasta no gerenciador de arquivos |

## Desenvolvimento

```bash
# Lint e formatação
uv run ruff check .
uv run ruff format .

# Testes
uv run pytest

# Rodar sem abrir browser
uv run python app.py --no-browser
```

## Limitações

- **Instagram:** apenas conteúdo público (posts, reels de contas públicas). Contas privadas não são suportadas.
- **YouTube:** vídeos com DRM ou restrição de idade podem falhar
- **Playlists:** vídeos removidos ou privados na conta de origem não são copiados
- **Windows:** o botão "abrir pasta" usa `explorer` automaticamente no Windows, `open` no macOS e `xdg-open` no Linux.

## Licença

MIT
