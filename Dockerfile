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

# Space-separated CLI names; use "none" for the toolchain without AI CLIs.
ARG AI_CLIS="claude codex agy grok pi"
RUN set -eu; set -f; set -- $AI_CLIS; \
    [ "$#" -gt 0 ] || { echo 'AI_CLIS must contain CLI names or "none".' >&2; exit 1; }; \
    packages=""; agy=false; pi=false; \
    for cli do \
        case "$cli" in \
            claude) packages="$packages @anthropic-ai/claude-code@latest" ;; \
            codex) packages="$packages @openai/codex@latest" ;; \
            grok) packages="$packages @xai-official/grok@latest" ;; \
            pi) packages="$packages @earendil-works/pi-coding-agent@latest"; pi=true ;; \
            agy) agy=true ;; \
            none) [ "$#" -eq 1 ] || { echo 'Use none by itself.' >&2; exit 1; } ;; \
            *) echo "Unknown AI CLI: $cli" >&2; exit 1 ;; \
        esac; \
    done; \
    if [ -n "$packages" ]; then npm install -g $packages; fi; \
    if "$pi"; then ln -sf "$(command -v pi)" /usr/local/bin/pi-coding-agent; fi; \
    if "$agy"; then \
        curl -fsSL https://antigravity.google/cli/install.sh -o /tmp/install-agy.sh; \
        bash /tmp/install-agy.sh --dir /usr/local/bin; \
        rm /tmp/install-agy.sh; \
    fi

RUN git config --system --add safe.directory '*'

WORKDIR /workspace

CMD ["/bin/bash"]
