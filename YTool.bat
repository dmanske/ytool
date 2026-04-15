@echo off
cd /d "%~dp0"
uv sync --quiet
uv run python app.py
