#!/usr/bin/env bash
# Install hub to ~/.local/bin and wire shell env (SEALHUB_*).
# Usage: install-hub-cli.sh /path/to/hub-binary [env-template-file]
set -euo pipefail

HUB_SRC="${1:?hub binary path required}"
ENV_TEMPLATE="${2:-}"

BIN_DIR="${HOME}/.local/bin"
ENV_DIR="${HOME}/.config/sealhub"
ENV_FILE="${ENV_DIR}/env"
MARK_BEGIN="# >>> sealhub hub cli >>>"
MARK_END="# <<< sealhub hub cli <<<"

mkdir -p "$BIN_DIR" "$ENV_DIR"
install -m 755 "$HUB_SRC" "${BIN_DIR}/hub"

if [[ -n "$ENV_TEMPLATE" && -f "$ENV_TEMPLATE" && ! -f "$ENV_FILE" ]]; then
  cp "$ENV_TEMPLATE" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Created $ENV_FILE — set SEALHUB_TOKEN if needed."
elif [[ ! -f "$ENV_FILE" ]]; then
  cat >"$ENV_FILE" <<'EOF'
export SEALHUB_SERVER="http://127.0.0.1:8080"
export SEALHUB_TOKEN=""
EOF
  chmod 600 "$ENV_FILE"
  echo "Created minimal $ENV_FILE — set SEALHUB_TOKEN."
fi

profile_snippet() {
  cat <<EOF
$MARK_BEGIN
export PATH="\$HOME/.local/bin:\$PATH"
if [[ -f "\$HOME/.config/sealhub/env" ]]; then
  # shellcheck disable=SC1091
  source "\$HOME/.config/sealhub/env"
fi
$MARK_END
EOF
}

update_profile() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  if grep -qF "$MARK_BEGIN" "$f" 2>/dev/null; then
    return 0
  fi
  printf '\n%s\n' "$(profile_snippet)" >>"$f"
}

update_profile "${HOME}/.bashrc"
update_profile "${HOME}/.profile"
if [[ -n "${ZDOTDIR:-}" && -f "${ZDOTDIR}/.zshrc" ]]; then
  update_profile "${ZDOTDIR}/.zshrc"
elif [[ -f "${HOME}/.zshrc" ]]; then
  update_profile "${HOME}/.zshrc"
fi

echo "Installed ${BIN_DIR}/hub"
echo "Open a new shell or: source ${ENV_FILE}"
