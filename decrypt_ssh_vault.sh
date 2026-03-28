#!/usr/bin/env bash
set -euo pipefail

VAULT_FILE="./id_ed25519.vault"
OUTPUT_KEY="$HOME/.ssh/6eniu5_id_ed25519"
VAULT_PASS=""
KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"

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
Usage: ./decrypt_ssh_vault.sh [options]

Options:
  --vault-file PATH     Encrypted vault file (default: ./id_ed25519.vault)
  --output-key PATH    Output key path (default: ~/.ssh/6eniu5_id_ed25519)
  --vault-pass PASS     Vault password (optional; if omitted, ansible-vault will prompt)
  --known-hosts PATH   known_hosts file (default: ~/.ssh/known_hosts)
  --skip-known-hosts    Do not add github.com to known_hosts
  -h, --help             Show help
HELP
}

SKIP_KNOWN_HOSTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault-file)
      VAULT_FILE="$2"; shift 2 ;;
    --output-key)
      OUTPUT_KEY="$2"; shift 2 ;;
    --vault-pass)
      VAULT_PASS="$2"; shift 2 ;;
    --known-hosts)
      KNOWN_HOSTS_FILE="$2"; shift 2 ;;
    --skip-known-hosts)
      SKIP_KNOWN_HOSTS=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -f "$VAULT_FILE" ]]; then
  echo "Vault file not found: $VAULT_FILE" >&2
  exit 1
fi

if ! command -v ansible-vault >/dev/null 2>&1; then
  echo "ansible-vault not found." >&2
  if command -v brew >/dev/null 2>&1; then
    echo "Installing ansible via Homebrew..."
    brew install ansible
  else
    echo "Install ansible (provides ansible-vault) first." >&2
    exit 1
  fi
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh" 2>/dev/null || true

if [[ -e "$OUTPUT_KEY" ]]; then
  if ! prompt_yes_no "${OUTPUT_KEY} already exists. Overwrite it?" n; then
    echo "Skipping decrypt (key already exists)."
  else
    rm -f "$OUTPUT_KEY"
  fi
fi

if [[ ! -e "$OUTPUT_KEY" ]]; then
  VAULT_PASSWORD_FILE=""
  if [[ -n "$VAULT_PASS" ]]; then
    VAULT_PASSWORD_FILE="$(mktemp)"
    chmod 600 "$VAULT_PASSWORD_FILE"
    printf '%s' "$VAULT_PASS" > "$VAULT_PASSWORD_FILE"
    trap 'rm -f "$VAULT_PASSWORD_FILE"' EXIT
  fi

  if [[ -n "$VAULT_PASSWORD_FILE" ]]; then
    ansible-vault decrypt "$VAULT_FILE" --output "$OUTPUT_KEY" --vault-password-file "$VAULT_PASSWORD_FILE"
  else
    ansible-vault decrypt "$VAULT_FILE" --output "$OUTPUT_KEY"
  fi

  chmod 600 "$OUTPUT_KEY" 2>/dev/null || true
fi

echo "SSH key ready: $OUTPUT_KEY"

if [[ "$SKIP_KNOWN_HOSTS" -eq 0 ]]; then
  if [[ ! -f "$KNOWN_HOSTS_FILE" ]]; then
    touch "$KNOWN_HOSTS_FILE" 2>/dev/null || true
  fi

  if ! ssh-keygen -F github.com -f "$KNOWN_HOSTS_FILE" >/dev/null 2>&1; then
    ssh-keyscan -H github.com >> "$KNOWN_HOSTS_FILE" 2>/dev/null || true
  fi

  chmod 644 "$KNOWN_HOSTS_FILE" 2>/dev/null || true
fi

echo "Done."

if prompt_yes_no "Run optional SSH auth test (this key only, via ssh -i)?" n; then
  if [[ -f "$OUTPUT_KEY" ]]; then
    ssh -i "$OUTPUT_KEY" -o IdentitiesOnly=yes -T git@github.com || true
  else
    echo "Key not present at $OUTPUT_KEY; skipping test." >&2
  fi
fi
