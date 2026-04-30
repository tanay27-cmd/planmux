#!/usr/bin/env bash
# proxycli — install CLIProxyAPI and authenticate Claude + Codex via OAuth so
# a single local endpoint serves Claude and OpenAI requests billed to your
# Claude/ChatGPT subscriptions instead of API credit.

set -euo pipefail

REPO="router-for-me/CLIProxyAPI"
INSTALL_DIR="${INSTALL_DIR:-$HOME/bin}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.cli-proxy-api}"
PORT="${PORT:-8317}"
HOST="${HOST:-127.0.0.1}"

log() { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

detect_asset() {
  local os arch
  case "$(uname -s)" in
    Darwin) os=darwin ;;
    Linux)  os=linux ;;
    *) err "unsupported OS: $(uname -s) — see manual install in README" ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch=arm64 ;;
    x86_64|amd64)  arch=amd64 ;;
    *) err "unsupported arch: $(uname -m)" ;;
  esac
  echo "${os}_${arch}"
}

require() {
  command -v "$1" >/dev/null 2>&1 || err "missing '$1' — install it and re-run"
}

build_from_source() {
  require go
  log "building from source via 'go build ./cmd/server'"
  mkdir -p "$INSTALL_DIR"
  ( cd "$(dirname "$0")" && go build -o "${INSTALL_DIR}/cliproxyapi" ./cmd/server )
  log "installed -> ${INSTALL_DIR}/cliproxyapi (built from source)"
}

install_binary() {
  if [ -n "${BUILD_FROM_SOURCE:-}" ]; then
    build_from_source
    return
  fi

  require curl
  require tar

  local platform tag asset url tmp
  platform=$(detect_asset)
  tag=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
  [ -n "$tag" ] || err "could not resolve latest release tag"

  asset="CLIProxyAPI_${tag#v}_${platform}.tar.gz"
  url="https://github.com/${REPO}/releases/download/${tag}/${asset}"
  tmp=$(mktemp -d)

  log "downloading ${asset}"
  curl -fsSL "$url" -o "${tmp}/${asset}" || err "download failed: $url"

  log "extracting"
  tar -xzf "${tmp}/${asset}" -C "$tmp"

  mkdir -p "$INSTALL_DIR"
  local bin
  bin=$(find "$tmp" -maxdepth 2 -type f \( -name 'cli-proxy-api*' -o -name 'cliproxyapi*' \) -perm -u+x | head -1)
  [ -n "$bin" ] || err "binary not found in archive"
  install -m 0755 "$bin" "${INSTALL_DIR}/cliproxyapi"
  rm -rf "$tmp"
  log "installed -> ${INSTALL_DIR}/cliproxyapi (${tag})"
}

write_config() {
  mkdir -p "$CONFIG_DIR"
  local cfg="${CONFIG_DIR}/config.yaml"
  if [ -f "$cfg" ]; then
    log "config exists at ${cfg} — leaving it alone"
    return
  fi
  local key
  key=$(head -c 32 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')
  cat > "$cfg" <<EOF
host: "${HOST}"
port: ${PORT}
auth-dir: "${CONFIG_DIR}"
api-keys:
  - "${key}"
debug: false
EOF
  log "wrote ${cfg}"
  log "API key: ${key}"
}

claude_login() {
  if ls "${CONFIG_DIR}"/claude-*.json >/dev/null 2>&1; then
    log "Claude auth already present — skipping"
    return
  fi
  log "starting Claude OAuth (a browser window will open; sign in with your Claude account)"
  "${INSTALL_DIR}/cliproxyapi" -config "${CONFIG_DIR}/config.yaml" -claude-login
}

codex_login() {
  if ls "${CONFIG_DIR}"/codex-*.json >/dev/null 2>&1; then
    log "Codex auth already present — skipping"
    return
  fi
  log "starting Codex OAuth (sign in with your ChatGPT Plus/Pro/Team account)"
  if [ -n "${CODEX_DEVICE_FLOW:-}" ]; then
    "${INSTALL_DIR}/cliproxyapi" -config "${CONFIG_DIR}/config.yaml" -codex-device-login
  else
    "${INSTALL_DIR}/cliproxyapi" -config "${CONFIG_DIR}/config.yaml" -codex-login
  fi
}

print_summary() {
  local key
  key=$(grep -E '^\s*-\s*"' "${CONFIG_DIR}/config.yaml" | head -1 | sed -E 's/.*"(.*)".*/\1/')
  cat <<EOF

==========================================================
  proxycli is ready

  Base URL : http://${HOST}:${PORT}
  API key  : ${key}

  Start the server:
    ${INSTALL_DIR}/cliproxyapi -config ${CONFIG_DIR}/config.yaml

  Use it as drop-in OpenAI / Anthropic / Gemini endpoint.
  Image generation (model: gpt-image-2) is billed to your
  ChatGPT plan, not API credit — see README "Image generation".
==========================================================
EOF
}

main() {
  install_binary
  write_config
  claude_login
  codex_login
  print_summary
}

main "$@"
