FROM node:20-slim

# System tools
RUN apt-get update && apt-get install -y \
    curl \
    git \
    gnupg \
    jq \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
 && apt-get update && apt-get install -y gh \
 && rm -rf /var/lib/apt/lists/*
RUN gh --version

# Avoid broken npm token during build
RUN npm config delete //registry.npmjs.org/:_authToken || true

# AI agent CLIs
RUN npm install -g @anthropic-ai/claude-code @sourcegraph/amp

# gh-token (GitHub App token generator)
ARG GH_TOKEN_VERSION=2.1.1
RUN curl -fsSL "https://github.com/Link-/gh-token/releases/download/v${GH_TOKEN_VERSION}/gh-token_linux_$(dpkg --print-architecture)" \
    -o /usr/local/bin/gh-token \
 && chmod +x /usr/local/bin/gh-token

# Create non-root user with host UID/GID
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN groupadd -g ${HOST_GID} -o agent 2>/dev/null || true \
 && useradd -m -u ${HOST_UID} -g ${HOST_GID} -o -s /bin/bash agent \
 && usermod -aG node agent
USER agent

WORKDIR /workspace
CMD ["sleep", "infinity"]
