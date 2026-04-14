# YTool

Aplicação web local para download de vídeos/áudios do YouTube e Instagram, e gerenciamento de inscrições e playlists entre contas do YouTube.

![Python 3.12+](https://img.shields.io/badge/Python-3.12+-3776AB?logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?logo=fastapi&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

## Funcionalidades

### Downloads
- Baixa vídeos e áudios do **YouTube** e **Instagram** (conteúdo público)
- Inspeção de formatos disponíveis antes do download
- Seleção de qualidade (4K, 1080p, 720p, 480p, 360p), formato (mp4, webm, mkv) e categoria
- Modo somente áudio (extrai MP3)
- Download de legendas com seleção de idiomas
- Progresso em tempo real via SSE (Server-Sent Events)
- Organização automática por plataforma e categoria
- Notificação nativa ao concluir

### Inscrições YouTube
- **Exportar** inscrições de uma conta para JSON/CSV
- **Importar** inscrições de um arquivo para outra conta
- **Transferir** inscrições diretamente entre duas contas
- Progresso em tempo real com rate limiting automático (~1 req/s)

### Playlists YouTube
- Listar todas as playlists (públicas e privadas) de uma conta
- Copiar playlists selecionadas entre contas
- Preserva privacidade (playlists privadas são recriadas como privadas)
- Progresso detalhado por playlist e por vídeo

## Screenshots

A interface possui tema escuro (padrão) e claro, com sidebar de navegação e quatro seções: Downloads, Inscrições, Playlists e Configurações.

## Requisitos

- **Python 3.12+**
- **uv** (gerenciador de pacotes) — [instalação](https://docs.astral.sh/uv/getting-started/installation/)
- **yt-dlp** (instalado automaticamente via dependências)
- **ffmpeg** (necessário para merge de áudio/vídeo) — `brew install ffmpeg`

## Instalação

```bash
git clone https://github.com/dmanske/ytool.git
cd ytool
uv sync
cp .env.example .env
```

## Uso

### Opção 1 — Terminal
```bash
uv run python app.py
```
O app abre automaticamente em `http://localhost:8000`.

### Opção 2 — Duplo clique (macOS)
Dê duplo clique no arquivo `YTool.command`. Ele instala dependências e inicia o servidor automaticamente.

## Configuração

### Variáveis de ambiente (.env)

```env
GOOGLE_CLIENT_ID=        # Necessário para Inscrições e Playlists
GOOGLE_CLIENT_SECRET=    # Necessário para Inscrições e Playlists
BASE_DOWNLOAD_DIR=~/Downloads/YTool
```

### Google OAuth (opcional)

Necessário apenas para os módulos de Inscrições e Playlists:

1. Acesse [Google Cloud Console](https://console.cloud.google.com/)
2. Crie um projeto e ative a **YouTube Data API v3**
3. Em **Credentials**, crie um **OAuth 2.0 Client ID** (tipo Web Application)
4. Adicione `http://localhost:8000/api/subscriptions/oauth/callback` como URI de redirecionamento
5. Copie o Client ID e Client Secret para o arquivo `.env`

## Stack

| Componente | Tecnologia |
|-----------|-----------|
| Backend | Python 3.12+, FastAPI, uvicorn |
| Downloads | yt-dlp via asyncio subprocess |
| Auth | google-auth-oauthlib, google-api-python-client |
| Frontend | HTML/CSS/JS vanilla + Tailwind CSS (CDN) |
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
│   ├── downloader.py        # Endpoints de download
│   ├── subscriptions.py     # Endpoints de inscrições e playlists
│   └── config.py            # Endpoints de configuração
├── services/
│   ├── ytdlp_service.py     # Lógica de download via yt-dlp
│   └── youtube_auth.py      # OAuth + operações YouTube API
└── static/
    ├── index.html           # SPA com 4 abas
    ├── app.js               # Lógica do frontend
    └── style.css            # Estilos + tema claro/escuro
```

## API

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/formats?url=` | Inspeciona formatos disponíveis |
| `POST` | `/api/download` | Inicia download (SSE) |
| `GET` | `/api/subscriptions/export` | Exporta inscrições (JSON/CSV) |
| `POST` | `/api/subscriptions/import` | Importa inscrições de arquivo (SSE) |
| `POST` | `/api/subscriptions/transfer` | Transfere inscrições entre contas (SSE) |
| `GET` | `/api/subscriptions/playlists` | Lista playlists da conta |
| `POST` | `/api/subscriptions/playlists/transfer` | Copia playlists entre contas (SSE) |
| `GET` | `/api/config` | Retorna configurações atuais |
| `POST` | `/api/config` | Salva configurações |

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

- **Instagram:** apenas conteúdo público (posts, reels de contas públicas)
- **YouTube:** vídeos com DRM ou restrição de idade podem falhar
- **Playlists:** vídeos removidos ou privados na origem não são copiados
- Não suporta download de playlists/canais inteiros (apenas vídeos individuais)

## Licença

MIT
