# Changelog

Todas as mudanças notáveis do projeto serão documentadas aqui.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.2.0] - 2026-04-18

### Adicionado
- Fila de downloads — adicione várias URLs e baixe em sequência
- Cancelar download em andamento
- Cortar trecho do vídeo (início/fim) via `--download-sections`
- Player do YouTube embutido pra prévia do vídeo
- Nome personalizado do arquivo antes de baixar
- Arrastar e soltar URL do navegador direto no campo
- Auto-inspecionar ao colar/arrastar URL
- Histórico persistente com thumbnails (~/.ytool/history.json)
- Botão limpar URL/prévia e limpar histórico
- Clique no histórico pra abrir pasta no Finder/Explorer
- Migração de playlists entre contas YouTube (públicas + privadas)
- Seleção de playlists via checkbox antes de transferir
- Tema claro/escuro com toggle na sidebar
- Sidebar lateral de navegação
- Layout otimizado pra telas grandes (27"+)
- Interface 100% em português brasileiro
- Modal de ajuda com guia completo
- Ícones YouTube/Instagram que acendem ao detectar plataforma
- Toasts no lugar de alert()
- Open-folder cross-platform (macOS/Windows/Linux)
- OAuth com select_account (2 contas sem 2 browsers)
- YTool.bat pra Windows
- Arquivo LICENSE (MIT)

### Corrigido
- Permissão de notificação movida pra evento de usuário (submit)
- Log toggle com label ID corrigido
- Validação de path no open-folder removida (causava 403 falso)
- Parâmetros trim_start/trim_end restaurados após refactor
- Argumentos inválidos do yt-dlp removidos (--remote-components)
- Import não usado removido (JSONResponse)

## [0.1.0] - 2025-12-01

### Adicionado
- Download de vídeos/áudios do YouTube e Instagram via yt-dlp
- Inspeção de formatos disponíveis
- Seleção de qualidade, formato e categoria
- Modo somente áudio (MP3)
- Download de legendas com seleção de idiomas
- Progresso em tempo real via SSE
- Exportar/importar/transferir inscrições YouTube
- OAuth Google pra autenticação
- Configuração de pasta de downloads e categorias
- Interface web com Tailwind CSS
- Launcher macOS (YTool.command)
