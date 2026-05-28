FROM node:22-slim

# ---------------------------------------------------------------------------
# System tools (always installed)
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
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Optional features — controlled via --build-arg at image build time
# ---------------------------------------------------------------------------
ARG INSTALL_DOTNET8=false
ARG INSTALL_DOTNET9=false
ARG INSTALL_DOTNET10=false
ARG INSTALL_CSHARP_LS=false
ARG INSTALL_PLAYWRIGHT=false

# ---------------------------------------------------------------------------
# .NET SDKs (optional: --build-arg INSTALL_DOTNET8/9/10=true)
# libicu72 is a .NET runtime dependency; installed only when .NET is needed.
# If only INSTALL_CSHARP_LS=true (no explicit dotnet flag), .NET 10 is used
# as the implicit runtime required by csharp-ls.
# ---------------------------------------------------------------------------
ENV PATH="${PATH}:/root/.dotnet/tools"
RUN if [ "$INSTALL_DOTNET8" = "true" ] || [ "$INSTALL_DOTNET9" = "true" ] || \
       [ "$INSTALL_DOTNET10" = "true" ] || [ "$INSTALL_CSHARP_LS" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends libicu72 \
        && rm -rf /var/lib/apt/lists/* \
        && curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
        && chmod +x /tmp/dotnet-install.sh \
        && if [ "$INSTALL_DOTNET8" = "true" ]; then \
             /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet; fi \
        && if [ "$INSTALL_DOTNET9" = "true" ]; then \
             /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet; fi \
        && if [ "$INSTALL_DOTNET10" = "true" ] || \
              ( [ "$INSTALL_CSHARP_LS" = "true" ] \
                && [ "$INSTALL_DOTNET8" != "true" ] \
                && [ "$INSTALL_DOTNET9" != "true" ] ); then \
             /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet; fi \
        && ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
        && rm /tmp/dotnet-install.sh; \
    fi

# ---------------------------------------------------------------------------
# C# Language Server (optional: --build-arg INSTALL_CSHARP_LS=true)
# ---------------------------------------------------------------------------
RUN if [ "$INSTALL_CSHARP_LS" = "true" ]; then \
      dotnet tool install -g csharp-ls; \
    fi

# ---------------------------------------------------------------------------
# Playwright CLI — Chromium only (optional: --build-arg INSTALL_PLAYWRIGHT=true)
# ---------------------------------------------------------------------------
RUN if [ "$INSTALL_PLAYWRIGHT" = "true" ]; then \
      npm install -g @playwright/test \
        && playwright install chromium --with-deps; \
    fi

# ---------------------------------------------------------------------------
# GitHub Copilot CLI (always installed)
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
