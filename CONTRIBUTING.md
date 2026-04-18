# Contribuindo com o YTool

Obrigado por querer contribuir! Este guia explica como configurar o ambiente e enviar suas mudanças.

## Setup rápido

```bash
# 1. Fork o repositório no GitHub e clone o seu fork
git clone https://github.com/SEU_USUARIO/ytool.git
cd ytool

# 2. Instale o uv (se não tiver)
# macOS/Linux:
curl -LsSf https://astral.sh/uv/install.sh | sh
# Windows:
# powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"

# 3. Instale dependências
uv sync

# 4. Copie o .env
cp .env.example .env

# 5. Rode o app
uv run python app.py
```

O app abre em `http://localhost:8000`.

## Fluxo de contribuição

1. Crie uma branch a partir da `main`:
   ```bash
   git checkout -b minha-feature
   ```

2. Faça suas mudanças

3. Rode o lint antes de commitar:
   ```bash
   uv run ruff check .
   uv run ruff format .
   ```

4. Faça commit seguindo o padrão:
   ```bash
   git commit -m "feat: descrição curta da mudança"
   ```

5. Push pro seu fork:
   ```bash
   git push origin minha-feature
   ```

6. Abra um **Pull Request** no GitHub apontando pra `dmanske/ytool:main`

## Padrão de commits

Usamos [Conventional Commits](https://www.conventionalcommits.org/):

| Prefixo | Quando usar |
|---------|------------|
| `feat:` | Nova funcionalidade |
| `fix:` | Correção de bug |
| `docs:` | Documentação |
| `style:` | Formatação (sem mudança de lógica) |
| `refactor:` | Refatoração de código |
| `chore:` | Manutenção (deps, config, CI) |

## Estrutura do projeto

```
app.py              → Entry point FastAPI
config.py           → Settings (pydantic-settings)
routers/            → Endpoints HTTP (sem lógica de negócio)
services/           → Lógica de negócio
static/             → Frontend (HTML/CSS/JS vanilla)
```

**Regras:**
- Routers só fazem roteamento — lógica fica em `services/`
- yt-dlp é chamado via `asyncio.subprocess`, nunca importado
- Progresso em tempo real sempre via SSE (`StreamingResponse`)
- Frontend é vanilla JS + Tailwind CDN — sem build step

## Padrões de código

- **Python:** ruff pra lint e formatação, type hints em tudo
- **Frontend:** vanilla JS, sem frameworks, Tailwind via CDN
- **Nomes:** em inglês no código, pt-BR na interface do usuário
- **Funções:** pequenas, fazem uma coisa só
- **Imports:** ordenados (ruff cuida disso)

## O que precisa de ajuda

Veja as [issues abertas](https://github.com/dmanske/ytool/issues) — as com label `good first issue` são ótimas pra começar.

## Dúvidas

Abra uma issue com a label `question` ou comente numa issue existente.
