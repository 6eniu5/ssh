# ssh repo (public)

This repo contains an encrypted payload for a **dedicated** SSH private key at **`~/.ssh/kernvex_id_ed25519`** (not `~/.ssh/id_ed25519`, so your default GitHub / SSH workflow elsewhere is unchanged).

> **How the identity system works:** [ARCHITECTURE.md](ARCHITECTURE.md) — the model behind `~/.ssh/config` + `~/.gitconfig`, and the public/private data strategy.
> **Adding a new company/client identity:** [ADDING_AN_IDENTITY.md](ADDING_AN_IDENTITY.md) — the invariants a folder-routed identity must satisfy (git, SSH, and the CLIs that have no folder awareness), plus a by-hand runbook that works on a machine holding nothing but this repo. `decrypt_ssh_vault.sh` here restores only the **personal** bootstrap key; every other key lives encrypted in a private repo, because this one is public.

## How Git uses this key (no global SSH side effects)

Bootstrap and `esetup/setup.sh` set **per-repository** `git config core.sshCommand` on:

- `~/kernvex/dotfiles` (submodules: `kickstart.nvim`, `tmux-sessionizer`)
- `~/kernvex/esetup` (after clone, in the bootstrap script)

That limits use of this key to those repos only. Your normal `ssh`, `scp`, and other Git repos keep using `~/.ssh/config` and the agent as before.

Override the key path anytime with the environment variable **`ESETUP_SSH_IDENTITY`** (same default path as above).

### Optional: `~/.ssh/config` host alias

If you prefer not to use `core.sshCommand`, you can add a **separate** host (does not override `Host github.com`):

```sshconfig
Host github.com-kernvex
  HostName github.com
  User git
  IdentityFile ~/.ssh/kernvex_id_ed25519
  IdentitiesOnly yes
```

Then use remotes like `git@github.com-kernvex:kernvex/esetup.git`. The scripts above do **not** require this block.

## Scripts

### 1) Decrypt only

Run after cloning this repo:

```bash
./decrypt_ssh_vault.sh
```

Default output: `~/.ssh/kernvex_id_ed25519`. Override with `--output-key PATH`.

You can optionally pass a vault password:

```bash
./decrypt_ssh_vault.sh --vault-pass 'YOUR_PASSWORD_HERE'
```

### 2) Full bootstrap (decrypt + clone + run `esetup`)

```bash
./bootstrap_esetup_from_ssh_repo.sh
```

Options:

- `--esetup-url URL` (default: https://github.com/kernvex/esetup.git)
- `--esetup-dir DIR` (default: ~/kernvex/esetup)
- `--output-key PATH` (default: ~/.ssh/kernvex_id_ed25519)
- `--vault-pass PASS` (optional)
- `--vault-file PATH` (default: ./id_ed25519.vault)
- `--skip-decrypt`
- `--skip-setup`

Environment:

- `ESETUP_DIR` — same as `--esetup-dir` (default `~/kernvex/esetup`)
- `TARGET_DOTFILES` — passed through to `esetup/setup.sh` (default `~/kernvex/dotfiles`)
- `ESETUP_SSH_IDENTITY` — same meaning as `--output-key`

Tip: clone this repo under `~/kernvex/ssh` so everything lives in `~/kernvex/`.
