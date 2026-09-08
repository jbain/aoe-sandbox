# aoe-docker

Slimmed sandbox images for [Agent of Empires](https://github.com/agent-of-empires/agent-of-empires).

| Image | Contents |
|---|---|
| `ghcr.io/jbain/aoe-slim` | Claude Code, Codex CLI, their ACP adapters, git, ripgrep, fzf, jq, Node 22 |
| `ghcr.io/jbain/aoe-slim-dev` | The above plus Go, uv, Playwright (+ Chromium), Caddy, `gh`, `logseq`, `logseq-pm`, tmux |

Built weekly for `linux/amd64` and `linux/arm64` (Apple Silicon, Raspberry Pi, Rockchip).

## Why

Upstream's `aoe-sandbox` bundles fifteen coding agents and weighs 8.6GB. This
keeps the two agents actually in use and drops the rest.

| Image | Size (arm64) |
|---|---|
| `aoe-sandbox` (upstream base) | 8.61 GB |
| `aoe-slim` (this base) | **1.54 GB** |
| `aoe-slim-dev` | **3.54 GB** |

### Where the size went

Layer cleanup only reclaims space when it happens in the **same `RUN`** that
created the waste — deleting in a later layer leaves the bytes in the lower
layer and makes the image bigger. Every optimization below is written that way.

| Change | Saved |
|---|---|
| Merged the Codex + ACP-adapter `npm install`s into one `RUN` | ~213 MB |
| Purged npm's cache (`/root/.npm`) in both images | ~280 MB |
| Dropped non-English logseq locales and the Chromium license dump | ~60 MB |

The npm merge is worth understanding: `@openai/codex` and
`@agentclientprotocol/codex-acp` each vendor the same 213 MB codex binary.
Installed as two separate `RUN`s they are stored twice; installed in one
command npm hoists the shared dependency and it is stored once.

Deliberately **not** removed:

- **`build-essential` (~300 MB)** — kept so agents can compile native npm
  modules (node-gyp) and cgo inside the sandbox.
- **The full Go distribution (238 MB)** — including `go/test` (the compiler's own
  test suite) and `go/api` (stdlib API compatibility manifests), ~28 MB that a
  container never reads. Left intact by choice. Note that `go/src` (163 MB) is
  *not* optional: since Go 1.20 the distribution ships no precompiled stdlib
  archives, so the compiler builds the standard library from that source.
- **Playwright's headless shell (266 MB)** — see the note below; removing it
  breaks the default launch path.

## Relationship to upstream

`docker/Dockerfile` is a **line-for-line derivative** of upstream's
`docker/Dockerfile`. Removed blocks are commented out in place and marked
`# [slim]` rather than deleted, so that:

- `diff` against upstream stays readable when pulling in changes, and
- re-enabling an agent means uncommenting its install block, its `mkdir` line,
  and its ACP adapter (if it has one).

To check for upstream drift:

```sh
diff -u /path/to/agent-of-empires/docker/Dockerfile docker/Dockerfile
```

`docker/Dockerfile.dev` follows upstream's structure but diverges more freely,
since its tool list is different by design.

## AoE compatibility

These are load-bearing; don't remove them when editing:

- `IS_SANDBOX=1` — lets Claude Code run `--dangerously-skip-permissions` as root
- `WORKDIR /workspace` — AoE mounts the project here
- `/root/.claude`, `/root/.codex`, `/root/.ssh` must exist as mount points; AoE
  bind-mounts per-session credential stores over them
- `claude` and `codex` must resolve on `PATH` (AoE detects agents by bare
  `which`), and AoE injects `CLAUDE_CONFIG_DIR=/root/.claude`
- **`claude-agent-acp` and `codex-acp` must be installed globally.** AoE's
  structured view `docker exec`s these by bare binary name; if they are absent
  the agent exits 127 and the ACP handshake times out.
- `/bin/sh` must exist — AoE execs `/bin/sh -c` for paired container terminals.
  `CMD` is overridden with `sleep infinity` by AoE, so the image's own `CMD` is
  informational.

## Usage

```sh
# Per-session
aoe add --sandbox-image ghcr.io/jbain/aoe-slim-dev:latest .
```

Or in `~/.agent-of-empires/config.toml`:

```toml
[sandbox]
default_image = "ghcr.io/jbain/aoe-slim-dev:latest"
```

## Building locally

```sh
docker build -f docker/Dockerfile -t aoe-slim:test docker/

docker build -f docker/Dockerfile.dev \
  --build-arg BASE_IMAGE=aoe-slim:test \
  --secret id=gh_token,env=GH_TOKEN \
  -t aoe-slim-dev:test docker/
```

The `gh_token` secret is optional locally. It is used for two things: lifting
the anonymous GitHub API rate limit when resolving the logseq nightly asset URL,
and cloning `logseq-project-management` while that repo is private.

## Notes on the dev image

- **logseq** ships no standalone CLI binary — the CLI is a JS entrypoint inside
  the desktop app's `app.asar`, run via the bundled Electron in
  `ELECTRON_RUN_AS_NODE=1` mode. `/usr/local/bin/logseq` is a shim doing exactly
  that, mirroring the one the macOS installer writes. Nightly asset names embed
  the version, so the download URL is resolved from the releases API at build
  time rather than pinned.
- **logseq-pm** installs from `github.com/jbain/logseq-project-management`. While
  that repo is private, `LOGSEQ_PM_OPTIONAL=1` (the current default) downgrades a
  failed install to a warning so the image still builds without a token. **Flip
  it to `0` once the repo is public** so a broken install fails the build.
- **Playwright** installs Chromium only, to `/opt/ms-playwright` rather than the
  default `~/.cache/ms-playwright` — AoE bind-mounts several `/root`
  subdirectories per session, and a browser store under `$HOME` is easy to
  shadow by accident. `NODE_PATH=/usr/lib/node_modules` is set so
  `require("playwright")` resolves from `/workspace`, not just the CLI.
- **Both Chromium builds are kept.** `playwright install chromium` lays down
  full Chromium (393 MB) *and* the headless shell (266 MB). A default
  `chromium.launch()` resolves to the **shell**, so deleting it breaks the
  common path with `Executable doesn't exist`. Beware that
  `chromium.executablePath()` reports the full-Chromium path even when the shell
  is what actually launches — it is not a safe way to conclude the shell is
  unused. Build with `--build-arg PLAYWRIGHT_ONLY_SHELL=1` to install only the
  shell (saves ~393 MB) if you never need headed browsing; headed mode
  otherwise works via `xvfb-run`.
- **Electron's GTK libraries** are installed explicitly before logseq. Playwright's
  `--with-deps chromium` does not cover them — Chromium's headless shell links a
  smaller set — and Electron loads GTK3 at process start even under
  `ELECTRON_RUN_AS_NODE`.
- **Node** comes from the base image. Upstream's dev image re-installs Node via
  nvm on top and symlinks over it; that block is present but commented out.
- **Rust** and **bun** are commented out. Uncomment if a project needs them.

## CI

`.github/workflows/build-images.yaml` runs weekly and on pushes touching
`docker/`. It calls the reusable `_build-image.yaml`, which builds each platform
on a **native runner** (`ubuntu-latest` / `ubuntu-24.04-arm`), pushes digest-only
images, then merges them into one manifest list. GitHub Actions layer cache is
scoped per image and per platform.

`ubuntu-24.04-arm` is free on public repositories; on a private repo it bills as
a larger runner. A commented single-job QEMU fallback is at the bottom of
`build-images.yaml`.

### Required secret

- `GHCR_BUILD_TOKEN` (optional) — PAT with `repo` scope. Needed only while
  `logseq-project-management` is private. Without it the dev image still builds,
  minus `logseq-pm`.
