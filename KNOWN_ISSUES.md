# Known Issues

## Homebrew caveats target zsh instead of fish

**Status:** Open  
**Affects:** First run of `setup.sh` (before fish is the default shell)

### Problem

`setup.sh` runs in bash (the shebang is `#!/usr/bin/env bash`), and the
login shell is still zsh when Homebrew formulas are installed. Homebrew
therefore installs shell completions into the **zsh** site-functions
directory rather than fish:

```
==> Caveats
zsh completions have been installed to:
  /opt/homebrew/share/zsh/site-functions
```

This was observed for at least **fnm** and **bun**, but applies to any
formula whose caveats include shell completions (e.g. eza, gh, etc.).

#### fnm install log (excerpt)

```
==> Running `brew cleanup fnm`...
Removing: /opt/homebrew/Cellar/fnm/1.38.1... (12 files, 7.5MB)
Removing: /Users/mowens/Library/Caches/Homebrew/fnm_bottle_manifest--1.38.1-1... (7.7KB)
Removing: /Users/mowens/Library/Caches/Homebrew/fnm--1.38.1... (3.3MB)
==> Caveats
zsh completions have been installed to:
  /opt/homebrew/share/zsh/site-functions
```

#### bun install log (excerpt)

```
==> Fetching downloads for: bun
==> Installing bun from oven-sh/bun
🍺  /opt/homebrew/Cellar/bun/1.3.11: 8 files, 61.1MB, built in 2 seconds
==> Running `brew cleanup bun`...
==> Caveats
zsh completions have been installed to:
  /opt/homebrew/share/zsh/site-functions
```

### Why it happens

1. `setup.sh` is a bash script invoked from a zsh login session.
2. Fish is installed *during* setup but is not the active shell yet.
3. Homebrew detects the current shell (zsh) and installs completions
   there.

### Current mitigation

`setup.sh` already collects caveat output and offers to run
`apply_known_caveat_actions`, which appends Homebrew's fish completion
paths to `~/dotfiles/fish/.config/fish/config.fish`:

```fish
if test -d (brew --prefix)/share/fish/completions
  set -p fish_complete_path (brew --prefix)/share/fish/completions
end
if test -d (brew --prefix)/share/fish/vendor_completions.d
  set -p fish_complete_path (brew --prefix)/share/fish/vendor_completions.d
end
```

This means fish **will** find completions that Homebrew places under its
own prefix, but the zsh-specific caveat message is misleading — the
completions still work in fish as long as the paths above are sourced.

### Possible improvements

- Set `SHELL` to the fish binary path before running `brew install` so
  Homebrew targets fish completions directly.
- Re-run `brew completions link` after switching the default shell to
  fish.
- Suppress the misleading zsh caveat output with
  `HOMEBREW_NO_ENV_HINTS=1`.

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

**Status:** Open  
**Affects:** First run of `setup.sh` (before fish is the default shell)  
**Related:** [Homebrew caveats target zsh instead of fish](#homebrew-caveats-target-zsh-instead-of-fish)

### Problem

After formula installation, Homebrew prints actionable caveat instructions
(e.g. "add this line to your `~/.zshrc`", "run `eval` in your shell
profile") that assume zsh is the active shell. Because the login shell is
still zsh when `setup.sh` runs, these instructions consistently reference
zsh config files and syntax instead of fish equivalents.

This means a user following the printed instructions verbatim would be
editing the wrong shell configuration — `.zshrc` or `.bash_profile`
instead of `config.fish`.

### Why it happens

Same root cause as the completions issue: Homebrew detects the current
shell (zsh) during `setup.sh` and tailors all caveat text — including
actionable "add this to your profile" instructions — to that shell.

### Current mitigation

None. The `apply_known_caveat_actions` helper addresses completions paths
but does not translate the ad-hoc shell-profile instructions that
individual formulas emit.

### Possible improvements

- Translate zsh-targeted caveat actions into fish equivalents in
  `apply_known_caveat_actions` (or a companion function).
- Set `SHELL` to the fish binary path before running `brew install` so
  Homebrew emits fish-appropriate instructions from the start.
- Document common formula caveats and their fish equivalents in a
  reference table that `setup.sh` can print at the end of the run.
