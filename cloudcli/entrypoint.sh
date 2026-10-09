#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${CODE_SERVER_PASSWORD:?Définissez CODE_SERVER_PASSWORD dans .env}"
export ANTHROPIC_AUTH_TOKEN="${OLLAMA_API_KEY:-}"
export OPENAI_API_KEY="${OLLAMA_API_KEY:-}"
export PASSWORD="$CODE_SERVER_PASSWORD"
export ANTHROPIC_MODEL="${OLLAMA_MODEL:-${ANTHROPIC_MODEL:-glm-5.3-flash}}"
[[ "$ANTHROPIC_MODEL" =~ ^[a-zA-Z0-9][a-zA-Z0-9._:-]*$ ]] || {
    echo "OLLAMA_MODEL contient un nom de modèle invalide." >&2; exit 2;
}
export ANTHROPIC_DEFAULT_SONNET_MODEL="$ANTHROPIC_MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$ANTHROPIC_MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$ANTHROPIC_MODEL"

# Seulement les racines des volumes : aucun parcours du workspace au démarrage.
sudo chown agent:agent /home/agent/.cloudcli /home/agent/.claude \
    /home/agent/.codex /home/agent/workspace /home/agent/.config/code-server \
    /home/agent/.local/share/code-server

# Les shells héritent de l'environnement : aucune clé ajoutée à .bashrc.
# Conserver les paramètres Claude existants et fusionner uniquement env.
settings=/home/agent/.claude/settings.json
tmp=$(mktemp /home/agent/.claude/settings.XXXXXX)
trap 'rm -f "$tmp"' EXIT
if [ ! -f "$settings" ]; then printf '{}\n' > "$settings"; fi
jq '.env = ((.env // {}) + {
    ANTHROPIC_BASE_URL: env.ANTHROPIC_BASE_URL,
    ANTHROPIC_AUTH_TOKEN: env.ANTHROPIC_AUTH_TOKEN,
    ANTHROPIC_API_KEY: "",
    ANTHROPIC_MODEL: env.ANTHROPIC_MODEL,
    ANTHROPIC_DEFAULT_SONNET_MODEL: env.ANTHROPIC_MODEL,
    ANTHROPIC_DEFAULT_HAIKU_MODEL: env.ANTHROPIC_MODEL,
    ANTHROPIC_DEFAULT_OPUS_MODEL: env.ANTHROPIC_MODEL
})' "$settings" > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$settings"
trap - EXIT

if [ ! -s /home/agent/.codex/config.toml ]; then
    cat > /home/agent/.codex/config.toml <<CODEOF
model_provider = "ollama_cloud"
model = "$ANTHROPIC_MODEL"
web_search = "disabled"

[model_providers.ollama_cloud]
name = "Ollama Cloud"
base_url = "https://ollama.com/v1"
env_key = "OLLAMA_API_KEY"
wire_api = "responses"
CODEOF
elif grep -q '^model_provider = "ollama_cloud"$' /home/agent/.codex/config.toml; then
    # Le modèle du fournisseur géré suit .env ; conserver les autres paramètres.
    sed -i "s/^model = .*/model = \"$ANTHROPIC_MODEL\"/" /home/agent/.codex/config.toml
fi
cat > /home/agent/.config/code-server/config.yaml <<'CODEOF'
bind-addr: 0.0.0.0:8080
auth: password
disable-telemetry: true
disable-update-check: true
CODEOF
cd /home/agent/workspace
exec "$@"
