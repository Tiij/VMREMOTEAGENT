# syntax=docker/dockerfile:1
FROM node:22-bookworm-slim
ARG CLOUDCLI_VERSION=1.37.4
ARG CODEX_VERSION=0.162.0
ARG CLAUDE_VERSION=2.1.295
ARG CODE_SERVER_VERSION=4.141.0
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8 TZ=Europe/Paris \
    NODE_OPTIONS="--max-old-space-size=384" \
    NPM_CONFIG_MAXSOCKETS=2 NPM_CONFIG_JOBS=1 PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

# Compilateurs temporaires, supprimés avec les caches dans la même couche.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates curl git jq sudo openssh-client procps supervisor tini \
       python3 ripgrep xz-utils build-essential \
    && npm install -g --omit=dev --no-audit --no-fund "@cloudcli-ai/cloudcli@${CLOUDCLI_VERSION}" \
    && npm install -g --omit=dev --no-audit --no-fund "@openai/codex@${CODEX_VERSION}" \
    && npm install -g --omit=dev --no-audit --no-fund "@anthropic-ai/claude-code@${CLAUDE_VERSION}" \
    && npm cache clean --force \
    && apt-get purge -y --auto-remove build-essential \
    && rm -rf /var/lib/apt/lists/* /root/.npm /root/.cache /tmp/*

# Archive autonome : pas de cache .deb ni d'installation Node supplémentaire.
RUN arch="$(dpkg --print-architecture)" \
    && curl -fL --retry 3 \
       "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${arch}.tar.gz" \
       | tar -xz -C /opt \
    && mv "/opt/code-server-${CODE_SERVER_VERSION}-linux-${arch}" /opt/code-server \
    && ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server

# La base Node fournit déjà l'uid 1000.
RUN groupmod -n agent node \
    && usermod -l agent -d /home/agent -m node \
    && printf 'agent ALL=(root) NOPASSWD: /usr/bin/chown\n' > /etc/sudoers.d/agent \
    && mkdir -p /home/agent/.cloudcli /home/agent/.claude /home/agent/.codex \
       /home/agent/.local/share/code-server /home/agent/.config/code-server \
       /home/agent/workspace /home/agent/.cache \
    && chown -R agent:agent /home/agent

ENV ANTHROPIC_BASE_URL=https://ollama.com ANTHROPIC_API_KEY="" \
    ANTHROPIC_MODEL=glm-5.3-flash OPENAI_BASE_URL=https://ollama.com/v1 \
    SERVER_PORT=3001 HOST=0.0.0.0 \
    DATABASE_PATH=/home/agent/.cloudcli/auth.db HOME=/home/agent
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY --chown=agent:agent --chmod=755 entrypoint.sh /home/agent/entrypoint.sh
WORKDIR /home/agent/workspace
USER agent
EXPOSE 3001 8080
ENTRYPOINT ["/usr/bin/tini", "--", "/home/agent/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
