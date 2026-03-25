#!/usr/bin/env bash
set -euo pipefail

ES_SETUP_URL="https://github.com/6eniu5/esetup.git"
ES_SETUP_DIR="$HOME/esetup"
VAULT_PASS=""
VAULT_FILE="./id_ed25519.vault"

SKIP_DECRYPT=0
SKIP_RUN_SETUP=0
SKIP_PREINSTALLED_BREW=0
SKIP_PREINSTALLED_ANSIBLE=0

log_info() { echo -e "\033[0;32m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[ERR]\033[0m $*" >&2; }

prompt_yes_no() {
  local msg="$1"
  local default="${2:-n}"
  local hint="[y/N]"
  [[ "$default" == "y" ]] && hint="[Y/n]"

  local ans=""
  read -r -p "${msg} ${hint} " ans || true
  ans="${ans:-}"

  if [[ -z "$ans" ]]; then
    [[ "$default" == "y" ]] && return 0
    return 1
  fi

  [[ "$ans" =~ ^[Yy]$ ]]
}

usage() {
  cat <<'HELP'
Usage: ./bootstrap_esetup_from_ssh_repo.sh [options]

Options:
  --esetup-url URL           esetup git URL (default: https://github.com/6eniu5/esetup.git)
  --esetup-dir DIR          Where to clone and run esetup (default: ~/esetup)
  --vault-pass PASS         ansible-vault password to decrypt id_ed25519.vault (optional)
  --vault-file PATH         Encrypted vault file (default: ./id_ed25519.vault)
  --skip-decrypt            Skip key decryption step
  --skip-setup              Skip running esetup/setup.sh (still clones)
  --help                    Show help
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --esetup-url) ES_SETUP_URL="$2"; shift 2 ;;
    --esetup-dir) ES_SETUP_DIR="$2"; shift 2 ;;
    --vault-pass) VAULT_PASS="$2"; shift 2 ;;
    --vault-file) VAULT_FILE="$2"; shift 2 ;;
    --skip-decrypt) SKIP_DECRYPT=1; shift ;;
    --skip-setup) SKIP_RUN_SETUP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

ensure_xcode_cli() {
  log_info "Ensuring Xcode Command Line Tools..."
  xcode-select --install 2>/dev/null || true
}

ensure_brew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  local arch
  arch="$(uname -m)"
  local brew_prefix
  if [[ "$arch" == "arm64" ]]; then
    brew_prefix="/opt/homebrew"
  else
    brew_prefix="/usr/local"
  fi

  if [[ ! -x "${brew_prefix}/bin/brew" ]]; then
    log_info "Installing Homebrew (${brew_prefix})..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  eval "$("${brew_prefix}/bin/brew" shellenv)"
}

ensure_ansible() {
  if [[ "$SKIP_PREINSTALLED_ANSIBLE" -eq 1 ]]; then
    return 0
  fi

  if command -v ansible-vault >/dev/null 2>&1; then
    return 0
  fi

  log_info "Installing ansible (provides ansible-vault)..."
  brew install ansible
}

ensure_brew_writable() {
  if ! command -v brew >/dev/null 2>&1; then
    return 0
  fi

  local bp
  bp="$(brew --prefix 2>/dev/null || true)"
  if [[ -z "$bp" ]]; then
    return 0
  fi

  if [[ -w "$bp" ]]; then
    return 0
  fi

  log_error "Homebrew prefix is not writable for this user: $bp"
  echo "Run these commands once, then re-run this script:"
  echo "  sudo chown -R $(id -un) \"$bp\""
  echo "  chmod u+w \"$bp\""
  exit 1
}

decrypt_key() {
  if [[ "$SKIP_DECRYPT" -eq 1 ]]; then
    log_warn "Skipping decrypt step (--skip-decrypt)."
    return 0
  fi

  if [[ ! -f "$VAULT_FILE" ]]; then
    log_error "Vault file not found: $VAULT_FILE"
    exit 1
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local decrypt_script
  decrypt_script="${script_dir}/decrypt_ssh_vault.sh"

  if [[ ! -x "$decrypt_script" ]]; then
    log_error "decrypt script missing or not executable: $decrypt_script"
    exit 1
  fi

  local args=()
  args+=("--vault-file" "$VAULT_FILE")

  if [[ -n "$VAULT_PASS" ]]; then
    args+=("--vault-pass" "$VAULT_PASS")
  fi

  if [[ "${args[*]:-}" != "" ]]; then
    "$decrypt_script" "${args[@]}"
  else
    "$decrypt_script"
  fi
}

clone_esetup() {
  if [[ -d "$ES_SETUP_DIR/.git" ]]; then
    if prompt_yes_no "${ES_SETUP_DIR} already exists. Re-clone/replace?" n; then
      rm -rf "$ES_SETUP_DIR"
    else
      log_warn "Keeping existing ${ES_SETUP_DIR}."
      return 0
    fi
  fi

  mkdir -p "$(dirname "$ES_SETUP_DIR")"
  log_info "Cloning esetup into ${ES_SETUP_DIR}..."
  git clone "$ES_SETUP_URL" "$ES_SETUP_DIR"
}

run_esetup() {
  if [[ "$SKIP_RUN_SETUP" -eq 1 ]]; then
    log_warn "Skipping running esetup (--skip-setup)."
    return 0
  fi

  log_info "Running esetup/setup.sh..."
  if [[ -x "$ES_SETUP_DIR/setup.sh" ]]; then
    chmod +x "$ES_SETUP_DIR/setup.sh" 2>/dev/null || true
    "$ES_SETUP_DIR/setup.sh"
    return 0
  fi

  if [[ -x "$ES_SETUP_DIR/esetup/setup.sh" ]]; then
    chmod +x "$ES_SETUP_DIR/esetup/setup.sh" 2>/dev/null || true
    "$ES_SETUP_DIR/esetup/setup.sh"
    return 0
  fi

  log_error "Could not find setup.sh in cloned repo."
  log_error "Checked: $ES_SETUP_DIR/setup.sh and $ES_SETUP_DIR/esetup/setup.sh"
  exit 1
}

main() {
  log_info "Bootstrap started (esetup + encrypted ssh key)."

  ensure_xcode_cli
  ensure_brew
  ensure_brew_writable
  ensure_ansible

  decrypt_key
  clone_esetup
  run_esetup

  log_info "All steps complete."
}

main "$@"
