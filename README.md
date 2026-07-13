# ssh repo (public)

This repo contains an encrypted payload for a **dedicated** SSH private key at **`~/.ssh/6eniu5_id_ed25519`** (not `~/.ssh/id_ed25519`, so your default GitHub / SSH workflow elsewhere is unchanged).

> **Adding another company/client identity?** See **[ADDING_AN_IDENTITY.md](ADDING_AN_IDENTITY.md)** — the step-by-step runbook for wiring a new folder-routed identity + its private `ssh-<initials>` key vault.

## How Git uses this key (no global SSH side effects)

Bootstrap and `esetup/setup.sh` set **per-repository** `git config core.sshCommand` on:

- `~/6eniu5/dotfiles` (submodules: `kickstart.nvim`, `tmux-sessionizer`)
- `~/6eniu5/esetup` (after clone, in the bootstrap script)

That limits use of this key to those repos only. Your normal `ssh`, `scp`, and other Git repos keep using `~/.ssh/config` and the agent as before.

Override the key path anytime with the environment variable **`ESETUP_SSH_IDENTITY`** (same default path as above).

### Optional: `~/.ssh/config` host alias

If you prefer not to use `core.sshCommand`, you can add a **separate** host (does not override `Host github.com`):

```sshconfig
Host github.com-6eniu5
  HostName github.com
  User git
  IdentityFile ~/.ssh/6eniu5_id_ed25519
  IdentitiesOnly yes
```

Then use remotes like `git@github.com-6eniu5:6eniu5/esetup.git`. The scripts above do **not** require this block.

## Scripts

### 1) Decrypt only

Run after cloning this repo:

```bash
./decrypt_ssh_vault.sh
```

Default output: `~/.ssh/6eniu5_id_ed25519`. Override with `--output-key PATH`.

You can optionally pass a vault password:

```bash
./decrypt_ssh_vault.sh --vault-pass 'YOUR_PASSWORD_HERE'
```

### 2) Full bootstrap (decrypt + clone + run `esetup`)

```bash
./bootstrap_esetup_from_ssh_repo.sh
```

Options:

- `--esetup-url URL` (default: https://github.com/6eniu5/esetup.git)
- `--esetup-dir DIR` (default: ~/6eniu5/esetup)
- `--output-key PATH` (default: ~/.ssh/6eniu5_id_ed25519)
- `--vault-pass PASS` (optional)
- `--vault-file PATH` (default: ./id_ed25519.vault)
- `--skip-decrypt`
- `--skip-setup`

Environment:

- `ESETUP_DIR` — same as `--esetup-dir` (default `~/6eniu5/esetup`)
- `TARGET_DOTFILES` — passed through to `esetup/setup.sh` (default `~/6eniu5/dotfiles`)
- `ESETUP_SSH_IDENTITY` — same meaning as `--output-key`

Tip: clone this repo under `~/6eniu5/ssh` so everything lives in `~/6eniu5/`.
