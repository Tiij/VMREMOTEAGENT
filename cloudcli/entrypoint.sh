#!/bin/bash
# ------------------------------------------------------------------
# Entrypoint : injecte la clé API réelle et prépare l'environnement
# avant de lancer cloudcli + code-server via supervisor.
# ------------------------------------------------------------------
set -e

KEY="${OLLAMA_API_KEY:-ollama}"

# Export de la clé pour le process supervisor
export ANTHROPIC_AUTH_TOKEN="$KEY"
export OPENAI_API_KEY="$KEY"

# Écrit les variables dans le .bashrc (shells lancés depuis CloudCLI / code-server)
cat >> /home/agent/.bashrc <<EOF
export OLLAMA_API_KEY="$KEY"
export ANTHROPIC_BASE_URL=https://ollama.com
export ANTHROPIC_AUTH_TOKEN="$KEY"
export ANTHROPIC_API_KEY=""
export ANTHROPIC_MODEL=qwen3-coder:cloud
export ANTHROPIC_SMALL_FAST_MODEL=qwen3-coder:cloud
export ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3-coder:cloud
export ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3-coder:cloud
export ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3-coder:cloud
export OPENAI_BASE_URL=https://ollama.com/v1
export OPENAI_API_KEY="$KEY"
EOF

# Persiste les paramètres Claude Code (CloudCLI spawn claude en PTY,
# il faut que ces valeurs soient dans ~/.claude/settings.json)
mkdir -p /home/agent/.claude
cat > /home/agent/.claude/settings.json <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://ollama.com",
    "ANTHROPIC_AUTH_TOKEN": "$KEY",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_SMALL_FAST_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "qwen3-coder:cloud",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "qwen3-coder:cloud"
  }
}
EOF

# S'assure que les dossiers persistent avec les bons droits
sudo chown -R agent:agent /home/agent/.cloudcli /home/agent/.claude \
                           /home/agent/.codex /home/agent/workspace \
                           /home/agent/.config /home/agent/.local 2>/dev/null || true

cd /home/agent/workspace
exec "$@"
