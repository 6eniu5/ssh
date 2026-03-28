# Known Issues

## Homebrew caveats target zsh instead of fish

**Status:** Fixed (see `6eniu5/esetup` `setup.sh`)  
**Affects:** Was: first run of `setup.sh` before fish was the default shell

### Problem (historical)

`setup.sh` ran in bash while the login shell was still zsh, so Homebrew
installed completions and printed caveats aimed at zsh.

### Resolution

In **`esetup/setup.sh`**: install **fish first**, then **`export SHELL="$(command -v fish)"`**
before the remaining `brew install` steps; run **`brew completions link`** after
all Homebrew installs (including optional Miniconda). **`apply_known_caveat_actions`**
still appends fish completion paths when needed.

In **`ssh/`**: when **`brew install ansible`** runs (bootstrap or decrypt scripts),
if **fish** is already on `PATH`, **`SHELL`** is set to fish first so caveats match.

---

## SSH key identity conflict: `~/.ssh/config` overrides per-repo `-i` key

**Status:** Fixed  
**Affects:** Any repo using the `6eniu5_id_ed25519` key on a machine that
also has a default `~/.ssh/config` `IdentityFile` for `github.com`

### Problem

After decrypting and deploying the `6eniu5_id_ed25519` key, git
operations (push, fetch) against `6eniu5/*` repos still authenticated as
the **wrong GitHub user** — the one associated with the machine's
pre-existing default key (`~/.ssh/id_ed25519`).

The scripts set `core.sshCommand` per-repo:

```bash
git config core.sshCommand 'ssh -i "~/.ssh/6eniu5_id_ed25519" -o IdentitiesOnly=yes'
```

The expectation was that `-o IdentitiesOnly=yes` combined with `-i`
would force SSH to use **only** the `6eniu5` key. However, the user's
`~/.ssh/config` contained:

```
Host github.com
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519
```

`IdentitiesOnly=yes` means "only use explicitly configured identity
files" — but **config-file `IdentityFile` directives count as explicitly
configured**. SSH offered both keys, tried the config-file key first,
GitHub accepted it, and the connection authenticated as the wrong user.

### Diagnosis

```bash
# With ~/.ssh/config active — wrong user:
ssh -i ~/.ssh/6eniu5_id_ed25519 -o IdentitiesOnly=yes -T git@github.com
# → Hi m0wens!

# Bypassing ~/.ssh/config — correct user:
ssh -F /dev/null -i ~/.ssh/6eniu5_id_ed25519 -o IdentitiesOnly=yes -T git@github.com
# → Hi 6eniu5!
```

### Fix

Add `-F /dev/null` to the SSH command so the user's `~/.ssh/config` is
ignored entirely when git runs SSH for that repo. The known_hosts file is
explicitly passed since `-F /dev/null` also drops the default
`UserKnownHostsFile`:

```bash
ssh -F /dev/null \
    -i "$ESETUP_SSH_IDENTITY" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$HOME/.ssh/known_hosts"
```

This fix was applied to:

- **`ssh/decrypt_ssh_vault.sh`** — the optional SSH auth test
- **`ssh/bootstrap_esetup_from_ssh_repo.sh`** — `configure_git_ssh_for_esetup_repo()`
  and `configure_git_ssh_for_ssh_repo()`
- **`esetup/setup.sh`** — `init_dotfiles_git()` where per-repo
  `core.sshCommand` is set for the dotfiles repo and submodules

### Why `-F /dev/null` is safe

`-F /dev/null` makes SSH read an empty config file. The only things lost
are convenience aliases and the default `IdentityFile` — both of which
we replace explicitly via `-i` and `-o UserKnownHostsFile`. OrbStack's
SSH config (`Include ~/.orbstack/ssh/config`) is also skipped, but that
only affects `orb` host aliases, not `github.com`.

---

## Actionable caveats at end of install reference the wrong shell

**Status:** Fixed (same fix as [Homebrew caveats target zsh instead of fish](#homebrew-caveats-target-zsh-instead-of-fish))  
**Affects:** Was: first run of `setup.sh` when caveat text assumed zsh

### Resolution

**`SHELL`** is set to the **fish** binary before the main batch of Homebrew
installs in `esetup/setup.sh`, so caveat instructions align with fish where
Homebrew supports it. Unusual formulas may still need manual follow-up.

---
