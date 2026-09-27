# aoe-slim: slimmed Docker image for Agent of Empires sandbox sessions
#
# This is a line-for-line derivative of the upstream
# agent-of-empires/agent-of-empires docker/Dockerfile. Blocks for agents we do
# not use are COMMENTED OUT IN PLACE rather than deleted, each marked with
# `# [slim]`, so that:
#
#   * `diff` against the upstream file stays small and readable when pulling
#     in updates, and
#   * re-enabling an agent is a matter of uncommenting its block plus its
#     `mkdir` line and (if it has one) its ACP adapter.
#
# Kept: Claude Code, Codex CLI. Everything else is disabled.
#
# Upstream header, for reference:
# This image provides Claude Code, OpenCode, Mistral Vibe, Hermes, Codex CLI, Gemini CLI, Antigravity CLI, Cursor CLI, Copilot CLI, Pi, OMP, Kiro CLI, Qwen Code, Kimi Code, and Prime Agent in an isolated environment

FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    jq \
    openssh-client \
    ripgrep \
    fzf \
    unzip \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (required for Codex CLI)
# [slim] Kept: Codex CLI and both ACP adapters below are npm packages, so Node
# [slim] is not optional even in the slim image.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Run as root - IS_SANDBOX=1 allows Claude Code to use --dangerously-skip-permissions
WORKDIR /root

# Install Claude Code CLI (official installer)
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"

# [slim] Install Oh My Pi (OMP) using its official prebuilt-binary installer
# [slim] RUN curl -fsSL https://omp.sh/install | sh

# [slim] Install OpenCode
# [slim] RUN curl -fsSL https://opencode.ai/install | bash
# [slim] ENV PATH="/root/.opencode/bin:${PATH}"

# [slim] Install Hermes (NousResearch/hermes-agent)
# [slim] --skip-setup avoids the interactive wizard; the FHS-style root install
# [slim] places `hermes` at /usr/local/bin and leaves config under /root/.hermes.
# [slim] RUN curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
# [slim]     | bash -s -- --skip-setup

# [slim] Install Codex CLI (OpenAI)
# [slim] MERGED with the ACP adapter install below -- see the note there. The
# [slim] original standalone line is kept here, commented, so the diff against
# [slim] upstream still shows where it used to be.
# [slim] RUN npm install -g @openai/codex

# [slim] Install Gemini CLI (Google)
# [slim] RUN npm install -g @google/gemini-cli

# [slim] Install Antigravity CLI (Google)
# [slim] RUN curl -fsSL https://antigravity.google/cli/install.sh | bash

# [slim] Install Mistral Vibe
# [slim] RUN curl -LsSf https://mistral.ai/vibe/install.sh | bash
# [slim] ENV PATH="/root/.vibe/bin:${PATH}"

# [slim] Install Cursor CLI
# [slim] RUN curl -fsSL https://cursor.com/install | bash

# [slim] Install Copilot CLI (GitHub)
# [slim] RUN npm install -g @github/copilot

# [slim] Install Pi (pi.dev). The pi-acp adapter (installed below alongside other
# [slim] structured view ACP adapters) shells out to the `pi` binary that this package
# [slim] provides, so the two packages are paired.
# [slim] RUN npm install -g @earendil-works/pi-coding-agent

# [slim] Install Kiro CLI (AWS)
# [slim] RUN curl -fsSL https://cli.kiro.dev/install | bash

# [slim] Install Qwen Code (Alibaba / QwenLM)
# [slim] RUN npm install -g @qwen-code/qwen-code

# [slim] Install Kimi Code (Moonshot AI). Ships its own native ACP server
# [slim] (`kimi acp`), so no separate adapter is needed below. Install to
# [slim] /usr/local (binary at /usr/local/bin/kimi) rather than the default
# [slim] ~/.kimi-code/bin: the aoe sandbox bind-mounts the host's ~/.kimi-code
# [slim] config over /root/.kimi-code, which would otherwise shadow the binary.
# [slim] RUN curl -fsSL https://code.kimi.com/kimi-code/install.sh \
# [slim]     | KIMI_INSTALL_DIR=/usr/local KIMI_NO_MODIFY_PATH=1 bash

# [slim] Install Prime Agent (PrimeIntellect). The installer is downloaded to a
# [slim] file first so a failed fetch fails the build instead of piping an empty
# [slim] script into sh, and `command -v` fails the build if no binary landed. The
# [slim] installer itself SHA-256-verifies the release tarball it installs. It
# [slim] detects the missing TTY in docker build and proceeds without its
# [slim] interactive confirmations; it needs npm (installed above) and lands the
# [slim] binary in npm's global bin directory, which the /root/.prime/agent config
# [slim] mount below does not shadow.
# [slim] RUN curl -fsSL https://app.primeintellect.ai/prime-agent/install.sh \
# [slim]         -o /tmp/install-prime-agent.sh \
# [slim]     && sh /tmp/install-prime-agent.sh \
# [slim]     && command -v prime-agent \
# [slim]     && rm /tmp/install-prime-agent.sh

# Install ACP adapters used by `aoe`'s structured view mode when the session is
# sandboxed. The structured view runner `docker exec`s these by their bare binary
# name (see `src/acp/agent_registry.rs`); if they aren't present in
# the image the agent process exits with status 127 and the ACP handshake
# times out. The list mirrors the npm-distributed adapters in
# `src/acp/install_hints.rs`; native adapters (`opencode acp`,
# `gemini --acp`, `vibe-acp`) are already provided by their respective
# CLIs above.
#
# [slim] Trimmed to the two adapters matching the agents we keep. These are NOT
# [slim] optional: without them, structured view sessions fail the handshake.
# [slim] `pi-acp` is dropped along with the Pi CLI it shells out to.
# [slim]
# [slim] STRUCTURAL DIVERGENCE FROM UPSTREAM: the Codex CLI install is folded
# [slim] into this RUN. `@openai/codex` and `@agentclientprotocol/codex-acp`
# [slim] each vendor their own copy of the same 213MB codex binary. A dedupe
# [slim] pass only reclaims space if it runs in the SAME layer that created the
# [slim] duplicate -- deleting or hardlinking in a later layer leaves the bytes
# [slim] sitting in the lower layer and makes the image bigger, not smaller.
# [slim] Hence one RUN. Together with dropping npm's 243MB cache this saves
# [slim] ~456MB.
# [slim] (upstream also installed `pi-acp` here; dropped with the Pi CLI.)
RUN npm install -g \
    @openai/codex \
    @agentclientprotocol/claude-agent-acp@^0.55.0 \
    @agentclientprotocol/codex-acp@latest \
    && find /usr/lib/node_modules -type f -size +1M -exec sha256sum {} + \
        | sort -k1,1 > /tmp/sums \
    && prev_hash= && prev_file= \
    && while read -r h f; do \
           if [ "$h" = "$prev_hash" ]; then ln -f "$prev_file" "$f"; \
           else prev_hash="$h"; prev_file="$f"; fi; \
       done < /tmp/sums \
    && rm -f /tmp/sums \
    && npm cache clean --force \
    && rm -rf /root/.npm

# Create directories for credential mounts
# [slim] Trimmed to the agents we keep, plus /root/.ssh and /root/.config, which
# [slim] aoe mounts unconditionally. Re-enabling an agent above means
# [slim] uncommenting its line here too.
RUN mkdir -p /root/.claude \
    /root/.codex \
    /root/.config \
    /root/.ssh
# [slim]     /root/.config/opencode \
# [slim]     /root/.local/share/opencode \
# [slim]     /root/.hermes \
# [slim]     /root/.vibe \
# [slim]     /root/.gemini \
# [slim]     /root/.gemini/antigravity-cli \
# [slim]     /root/.cursor \
# [slim]     /root/.copilot \
# [slim]     /root/.pi \
# [slim]     /root/.omp \
# [slim]     /root/.factory \
# [slim]     /root/.kiro \
# [slim]     /root/.qwen \
# [slim]     /root/.kimi-code \
# [slim]     /root/.prime/agent \

# Shell prompt (git branch/state, colorized), bash completions for git and
# gh, and colorized `ls`/`grep` output.
#
# Scripts are dropped into /etc/bash_completion.d/ and sourced by /root/.bashrc
# below -- this is self-contained (no reliance on a `bash-completion` apt
# package or distro-specific paths). git's scripts are fetched from upstream
# and pinned by tag; gh's completion script is generated by Dockerfile.dev
# right after `gh` is installed there, and lands in the same directory so it
# is picked up automatically without touching .bashrc again.
ARG GIT_PROMPT_REF=v2.47.0
RUN mkdir -p /etc/bash_completion.d \
    && curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
        "https://raw.githubusercontent.com/git/git/${GIT_PROMPT_REF}/contrib/completion/git-prompt.sh" \
        -o /etc/bash_completion.d/git-prompt.sh \
    && curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
        "https://raw.githubusercontent.com/git/git/${GIT_PROMPT_REF}/contrib/completion/git-completion.bash" \
        -o /etc/bash_completion.d/git-completion.bash

RUN printf '%s\n' \
    '# Source every completion/prompt script dropped in /etc/bash_completion.d' \
    '# (git-prompt.sh + git-completion.bash from the base image; gh from Dockerfile.dev)' \
    'if [ -d /etc/bash_completion.d ]; then' \
    '    for f in /etc/bash_completion.d/*; do' \
    '        [ -r "$f" ] && . "$f"' \
    '    done' \
    'fi' \
    '' \
    '# Show the current git branch/state in the prompt, colorized' \
    'export GIT_PS1_SHOWDIRTYSTATE=1' \
    'PS1='"'"'\[\e[32m\]\u@\h\[\e[0m\]:\[\e[34m\]\w\[\e[33m\]$(declare -F __git_ps1 >/dev/null && __git_ps1 " (%s)")\[\e[0m\]\$ '"'"'' \
    '' \
    '# Colorized ls/grep output' \
    'alias ls="ls --color=auto"' \
    'alias grep="grep --color=auto"' \
    > /root/.bashrc \
    && printf '%s\n' '[ -r ~/.bashrc ] && . ~/.bashrc' > /root/.bash_profile

# Ensure terminals identify as color-capable
ENV TERM=xterm-256color

# Podman install script (not run at build time -- see the script header for
# why): copied in so a session that actually needs nested containers can opt
# in with `install-podman` instead of every session paying for it by default.
COPY install-podman.sh /usr/local/bin/install-podman
RUN chmod +x /usr/local/bin/install-podman

# Allow Claude Code to use --dangerously-skip-permissions as root
ENV IS_SANDBOX=1

# Set working directory
WORKDIR /workspace

# Default command - keep container running for docker exec
CMD ["sleep", "infinity"]
