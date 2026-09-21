FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV SHELL=/bin/bash
LABEL org.opencontainers.image.source="https://github.com/jjjakob502/ai.cmd"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gh \
    openssh-client \
    ripgrep \
    jq \
    socat \
    netcat-openbsd \
    unzip \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    sudo \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g \
    @anthropic-ai/claude-code@latest \
    @openai/codex@latest \
    @xai-official/grok@latest \
    @earendil-works/pi-coding-agent@latest \
    && (command -v pi >/dev/null 2>&1 && ln -sf "$(command -v pi)" /usr/local/bin/pi-coding-agent || true)

RUN git config --system --add safe.directory '*'

RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin

WORKDIR /workspace

CMD ["/bin/bash"]
