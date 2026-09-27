# Per-task Claude Code sandbox (PLAN.md Phase 1). Built fresh, runs exactly
# one task, then the container is discarded — the image itself carries no
# task-specific state or credentials.
FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      gnupg \
      git \
      jq \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Non-root: --dangerously-skip-permissions removes Claude Code's own
# confirmation prompts, so container-level isolation (this user, the
# egress-allowlist proxy, the ephemeral filesystem) is what's left standing
# in for the human checkpoint that exists in an interactive session. Root
# inside the container would give a compromised/misdirected task more than
# it needs even though the container itself is disposable.
RUN useradd --create-home --shell /bin/bash agent
USER agent
WORKDIR /home/agent

# Project-level settings.json (tool/command allowlist) is picked up from
# CLAUDE_CONFIG_DIR rather than from the cloned repo, so it can't be
# overridden by anything checked into the target repo itself.
ENV CLAUDE_CONFIG_DIR=/home/agent/.claude-rbox
COPY --chown=agent:agent settings.json /home/agent/.claude-rbox/settings.json

COPY --chown=agent:agent entrypoint.sh /home/agent/entrypoint.sh
RUN chmod +x /home/agent/entrypoint.sh

ENTRYPOINT ["/home/agent/entrypoint.sh"]
