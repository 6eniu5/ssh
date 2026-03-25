# ssh repo (public)

This repo contains an encrypted payload for `~/.ssh/id_ed25519`.

## Scripts

### 1) Decrypt only

Run after cloning this repo:

```bash
./decrypt_ssh_vault.sh
```

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
- `--esetup-dir DIR` (default: ~/esetup)
- `--vault-pass PASS` (optional)
- `--skip-decrypt`
- `--skip-setup`

