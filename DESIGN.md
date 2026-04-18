# YTool — Design Document

## Understanding Summary

- **O que:** Aplicação web local com três módulos — downloader (YouTube + Instagram), gerenciador de inscrições YouTube, e migração de playlists
- **Por que:** Necessidade pessoal com potencial de virar produto público
- **Para quem:** Uso pessoal em macOS/Windows/Linux, depois distribuição pública
- **Constraints:** yt-dlp para downloads, OAuth Google para inscrições/playlists, interface web no browser
- **Não-objetivos:** monitoramento automático, app desktop nativo, Instagram privado

## Premissas

- `yt-dlp` cobre YouTube e Instagram sem API key
- OAuth Google necessário apenas para inscrições e playlists
- Instagram: apenas conteúdo público (evitar violação de ToS)
- Arquitetura não precisa ser otimizada para escala agora (YAGNI)
- Tokens OAuth salvos localmente em `~/.ytool/tokens/`
- Histórico de downloads salvo em `~/.ytool/history.json`

## Stack

- **Backend:** Python 3.12+, FastAPI, uvicorn
- **Downloads:** yt-dlp via asyncio subprocess (com cancel e trim)
- **Autenticação:** google-auth, google-auth-oauthlib, google-api-python-client
- **Frontend:** HTML/CSS/JS vanilla + Tailwind via CDN + Lucide Icons
- **Player:** YouTube IFrame API (prévia embutida)
- **Progresso em tempo real:** SSE (Server-Sent Events)
- **Dependências:** uv + pyproject.toml

## Estrutura do Projeto

```
ytool/
├── app.py                    # FastAPI app + lifespan
├── config.py                 # pydantic-settings
├── pyproject.toml
├── YTool.command              # Launcher macOS
├── YTool.bat                  # Launcher Windows
├── routers/
│   ├── downloader.py          # Download, cancel, formats, thumbnail, history
│   ├── subscriptions.py       # OAuth, subs, playlists
│   └── config.py              # Config, open-folder
├── services/
│   ├── ytdlp_service.py       # yt-dlp subprocess, progress, cancel
│   ├── youtube_auth.py        # OAuth + YouTube API operations
│   └── history_service.py     # Persistent download history
└── static/
    ├── index.html             # SPA com 4 abas + modal ajuda + player
    ├── app.js                 # Frontend (fila, drag-drop, tema, player)
    └── style.css              # Dark/light theme, sidebar, components
```

## Módulos

### Módulo 1 — Downloads

**Endpoints:** `POST /api/download`, `POST /api/download/cancel`, `GET /api/formats`, `GET /api/history`, `DELETE /api/history`

**Fluxo:**
1. Usuário cola URL → auto-inspeciona formatos e mostra prévia com player
2. Escolhe qualidade, formato, categoria, nome, trecho (opcional)
3. Clica Baixar (direto) ou Adicionar à Fila (múltiplas URLs)
4. yt-dlp roda via asyncio.subprocess com progresso SSE
5. Ao concluir, salva no histórico persistente com thumbnail
6. Pode cancelar a qualquer momento

**Features:**
- Fila de downloads sequencial
- Cancelamento via kill do processo
- Corte de trecho via `--download-sections`
- Nome personalizado do arquivo
- Drag & drop de URLs
- Auto-paste do clipboard
- Histórico persistente com thumbnails
- Abrir pasta no Finder/Explorer/Nautilus

### Módulo 2 — Inscrições YouTube

**Endpoints:** `GET /export`, `POST /import`, `POST /transfer`

**Fluxo:**
1. Conecta conta de origem e destino via OAuth (tela de seleção de conta)
2. Exporta → JSON/CSV, Importa → arquivo, ou Transfere direto A→B
3. Rate limiting ~1 req/s pra respeitar API do YouTube
4. Progresso via SSE

### Módulo 3 — Playlists YouTube

**Endpoints:** `GET /playlists`, `POST /playlists/transfer`

**Fluxo:**
1. Carrega playlists da conta de origem (públicas + privadas)
2. Seleciona quais copiar via checkbox
3. Recria na conta destino com mesmos vídeos e privacidade
4. Progresso duplo: por playlist + por vídeo

### UI — Quatro abas + Sidebar

**Downloads:** Formulário com URL, prévia, player, opções, fila, progresso, histórico
**Inscrições:** Cards de conta, exportar/importar/transferir, progresso
**Playlists:** Cards de conta, lista com checkbox, transferir, progresso duplo
**Config:** Pasta de downloads, categorias, Google OAuth status

**Extras:** Tema escuro/claro, modal de ajuda, toasts, ícones de plataforma

## Decision Log

| Decisão | Alternativas | Motivo |
|---------|-------------|--------|
| FastAPI + HTML vanilla | Electron, Next.js | Menor complexidade, cross-platform |
| yt-dlp para downloads | API oficial | Sem API key, suporta YouTube e Instagram |
| SSE para progresso | Polling, WebSocket | Mais simples que WS, resolve o problema |
| uv para dependências | pip + venv, Poetry | Mais rápido, moderno, pyproject.toml |
| OAuth Google | Cookies, scraping | Único módulo que exige auth oficial |
| Tokens em ~/.ytool/ | DB, sessão | Simples, seguro, persiste entre reinicializações |
| Tailwind via CDN | Bootstrap, CSS puro | Zero configuração, visual limpo |
| Lucide Icons via CDN | Heroicons, Font Awesome | Leve, moderno, tree-shakeable |
| YouTube IFrame API | Embed simples | Permite controle programático do player |
| Instagram só público | Login Instagram | Evita violação de ToS |
| Sidebar lateral | Header com tabs | Melhor uso de tela grande (27"+) |
| JSON pra histórico | SQLite, localStorage | Simples, portável, sem dependência extra |
| select_account no OAuth | Sessão única | Permite usar 2 contas sem 2 browsers |
| Cross-platform open-folder | macOS only | platform.system() detecta OS automaticamente |
