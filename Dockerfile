FROM node:22-slim

# ---------------------------------------------------------------------------
# System tools
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        git \
        jq \
        unzip \
        zip \
        python3 \
        python3-pip \
        python3-venv \
        libicu72 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# .NET SDKs (8, 9, 10) via Microsoft install script
# ---------------------------------------------------------------------------
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet \
    && /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet \
    && /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet \
    && ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh

# ---------------------------------------------------------------------------
# C# Language Server (csharp-ls via Roslyn)
# ---------------------------------------------------------------------------
ENV PATH="${PATH}:/root/.dotnet/tools"
RUN dotnet tool install -g csharp-ls

# ---------------------------------------------------------------------------
# Playwright CLI (Chromium only)
# ---------------------------------------------------------------------------
RUN npm install -g @playwright/test \
    && playwright install chromium --with-deps

# ---------------------------------------------------------------------------
# GitHub Copilot CLI
# ---------------------------------------------------------------------------
RUN npm install -g @github/copilot

# ---------------------------------------------------------------------------
# Status line script
# ---------------------------------------------------------------------------
RUN printf '#!/bin/bash\nif [ -n "$COPILOT_SANDBOX_SESSION" ]; then\n  echo "📁 $COPILOT_SANDBOX_SESSION"\nfi\n' \
    > /usr/local/bin/statusline-session.sh \
    && chmod +x /usr/local/bin/statusline-session.sh

WORKDIR /workspace

ENTRYPOINT ["copilot"]
