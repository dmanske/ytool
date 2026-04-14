# YTool — Design Document

## Understanding Summary

- **O que:** Aplicação web local com dois módulos — downloader (YouTube + Instagram) e gerenciador de inscrições YouTube
- **Por que:** Necessidade pessoal com potencial de virar produto público
- **Para quem:** Uso pessoal no Mac inicialmente, depois distribuição pública
- **Constraints:** yt-dlp para downloads, OAuth Google para inscrições, interface web no browser
- **Não-objetivos:** playlists/canais inteiros, monitoramento automático, app desktop

## Premissas

- `yt-dlp` cobre YouTube e Instagram sem API key
- OAuth Google necessário apenas para o módulo de inscrições
- Instagram: apenas conteúdo público (evitar violação de ToS)
- Arquitetura não precisa ser otimizada para escala agora (YAGNI)
- Tokens OAuth salvos localmente em `~/.ytool/tokens/`

## Stack

- **Backend:** Python 3.12+, FastAPI, uvicorn
- **Downloads:** yt-dlp via asyncio subprocess
- **Autenticação:** google-auth, google-auth-oauthlib, google-api-python-client
- **Frontend:** HTML/CSS/JS vanilla + Tailwind via CDN
- **Progresso em tempo real:** SSE (Server-Sent Events)
- **Dependências:** uv + pyproject.toml

## Estrutura do Projeto

```
youtube_downloader/
├── app.py
├── pyproject.toml
├── .env.example
├── .gitignore
├── routers/
│   ├── downloader.py
│   └── subscriptions.py
├── services/
│   ├── ytdlp_service.py
│   └── youtube_auth.py
├── static/
│   ├── index.html
│   ├── style.css
│   └── app.js
└── config.py
```

## Módulos

### Módulo 1 — Downloads

**Endpoint:** `POST /api/download`

**Request:**
```python
class DownloadRequest(BaseModel):
    url: str
    quality: str = "best"    # best, 1080p, 720p, 480p, 360p
    format: str = "mp4"      # mp4, webm, mkv
    audio_only: bool = False
    category: str
```

**Fluxo:**
1. Detecta plataforma pela URL (youtube.com / instagram.com)
2. Monta pasta: `{base_dir}/{plataforma}/{categoria}/`
3. Chama yt-dlp via asyncio.subprocess (não bloqueia o servidor)
4. Envia progresso via SSE
5. Retorna nome do arquivo ao concluir

### Módulo 2 — Inscrições YouTube

**Exportar:** `GET /api/subscriptions/export`
- Autentica conta via OAuth Google
- Busca inscrições paginando até o fim
- Retorna JSON ou CSV para download

**Importar:** `POST /api/subscriptions/import`
- Recebe arquivo .json/.csv
- Autentica conta destino
- Inscreve nos canais (~1/segundo por rate limit)
- Progresso via SSE

**Transferir:** `POST /api/subscriptions/transfer`
- Autentica conta A e conta B na mesma sessão
- Transfere direto sem arquivo intermediário
- Progresso via SSE

### UI — Três abas

**Downloads:**
- Campo URL + botão Baixar
- Seletores de qualidade, formato, categoria
- Barra de progresso SSE
- Histórico de downloads

**Inscrições:**
- Botão exportar conta A → arquivo
- Botão importar arquivo → conta B
- Botão transferir direto A → B
- Barra de progresso SSE

**Config:**
- Pasta base de downloads
- Gerenciar categorias
- Configurar credenciais Google (com guia passo a passo)
- Botão "Testar conexão"

## Decision Log

| Decisão | Alternativas | Motivo |
|---------|-------------|--------|
| FastAPI + HTML vanilla | Electron, Next.js | Menor complexidade, fácil distribuir |
| yt-dlp para downloads | API oficial | Sem API key, suporta YouTube e Instagram |
| SSE para progresso | Polling, WebSocket | Mais simples que WS, resolve o problema |
| uv para dependências | pip + venv, Poetry | Mais rápido, moderno, pyproject.toml |
| OAuth Google só para inscrições | Cookies, scraping | Único módulo que exige auth oficial |
| Tokens em ~/.ytool/tokens/ | DB, sessão | Simples, seguro, persiste entre reinicializações |
| Tailwind via CDN | Bootstrap, CSS puro | Zero configuração, visual limpo |
| Instagram só público | Login Instagram | Evita violação de ToS |

## Como Rodar

```bash
git clone ...
uv sync
cp .env.example .env
uv run python app.py   # abre localhost:8000 automaticamente
```
