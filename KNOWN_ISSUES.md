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
