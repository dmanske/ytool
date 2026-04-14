#!/bin/bash
cd "$(dirname "$0")"

# Mata processo antigo na porta 8000 se existir
lsof -ti:8000 | xargs kill -9 2>/dev/null

# Carrega PATH do shell (necessário pro uv funcionar)
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

uv sync --quiet
uv run python app.py
