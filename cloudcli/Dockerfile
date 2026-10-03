# =================================================================
# CloudCLI image : Debian Bookworm
# Installe :
#   - Node.js 22 + git / build tools / python3 / chromium (headless)
#   - @cloudcli-ai/cloudcli  (frontend web multi-agents, port 3001)
#   - @anthropic-ai/claude-code  (Claude Code)
#   - @openai/codex              (Codex CLI)
#   - code-server  (VS Code web, port 8080)
# Tous les agents sont préconfigurés pour taper sur Ollama Cloud.
# Les deux services (cloudcli + code-server) sont lancés par tini.
# =================================================================
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=Europe/Paris

# ---- Paquets système ----
# chromium est omis (non utilisé en serveur, sauve ~400 Mo d'espace disque
# et réduit drastiquement la RAM consommée pendant le build sur ARM64).
# Si vous voulez le navigateur headless pour du browser-use, ajoutez-le
# dans un deuxième temps.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git unzip zip jq sudo htop tmux neovim ripgrep fd-find \
      build-essential python3 python3-pip python3-venv pipx \
      openssh-client gnupg procps xz-utils supervisor tini \
      fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/*

# ---- Node.js 22 (requis par CloudCLI) ----
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g npm@latest

# ---- CLIs : Claude Code, Codex, CloudCLI ----
# On installe les paquets UN PAR UN avec une limite de mémoire Node
# et sans parallélisme pour éviter l'OOM (exit code 137) sur les VMs
# avec peu de RAM (1-2 Go), typiquement ARM64. Chaque RUN est une
# couche Docker séparée ce qui permet aussi de bénéficier du cache.
ENV NODE_OPTIONS="--max-old-space-size=1024" \
    NPM_CONFIG_FETCH_RETRIES=5 \
    NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=10000 \
    NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=60000 \
    NPM_CONFIG_JOBS=1 \
    NPM_CONFIG_MAXSOCKETS=1
RUN npm install -g @openai/codex
RUN npm install -g @anthropic-ai/claude-code
RUN npm install -g @cloudcli-ai/cloudcli

# ---- code-server (VS Code web) ----
RUN curl -fsSL https://code-server.dev/install.sh | sh \
    && rm -rf /var/lib/apt/lists/*

# ---- Utilisateur non-root ----
RUN useradd -m -u 1000 agent -s /bin/bash \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && mkdir -p /home/agent/.cloudcli /home/agent/.claude /home/agent/.codex \
                 /home/agent/.local/share/code-server \
                 /home/agent/workspace /home/agent/.cache \
    && chown -R agent:agent /home/agent

# ---- Config Codex : pointe sur Ollama Cloud (OpenAI-compat) ----
RUN cat > /home/agent/.codex/config.toml <<'EOF'
model_provider = "ollama_cloud"
model = "qwen3-coder:cloud"

[model_providers.ollama_cloud]
name = "Ollama Cloud"
base_url = "https://ollama.com/v1"
env_key = "OLLAMA_API_KEY"

oss_provider = "ollama_cloud"
EOF

# ---- Config code-server : désactive le mot de passe (Caddy fait l'auth si besoin)
RUN mkdir -p /home/agent/.config/code-server \
 && cat > /home/agent/.config/code-server/config.yaml <<'EOF'
bind-addr: 0.0.0.0:8080
auth: none
disable-telemetry: true
disable-update-check: true
EOF
RUN chown -R agent:agent /home/agent/.config

# ---- Variables d'environnement pointant vers Ollama Cloud ----
#     ANTHROPIC_BASE_URL pointe sur la RACINE du serveur : Claude Code
#     construit /v1/messages tout seul (donc PAS de /v1 à la fin).
ENV ANTHROPIC_BASE_URL=https://ollama.com \
    ANTHROPIC_AUTH_TOKEN=__OLLAMA_API_KEY__ \
    ANTHROPIC_API_KEY="" \
    ANTHROPIC_MODEL=qwen3-coder:cloud \
    ANTHROPIC_SMALL_FAST_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3-coder:cloud \
    ANTHROPIC_DEFAULT_OPUS_MODEL=qwen3-coder:cloud \
    OPENAI_BASE_URL=https://ollama.com/v1 \
    OPENAI_API_KEY=__OLLAMA_API_KEY__ \
    SERVER_PORT=3001 \
    HOST=0.0.0.0 \
    DATABASE_PATH=/home/agent/.cloudcli/auth.db

# ---- Supervisor : lance cloudcli + code-server en parallèle ----
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

WORKDIR /home/agent/workspace
USER agent

# Entrypoint qui remplace le placeholder __OLLAMA_API_KEY__
COPY --chown=agent:agent entrypoint.sh /home/agent/entrypoint.sh
USER root
RUN chmod +x /home/agent/entrypoint.sh && chown agent:agent /home/agent/entrypoint.sh
USER agent

EXPOSE 3001 8080
ENTRYPOINT ["/usr/bin/tini", "--", "/home/agent/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
