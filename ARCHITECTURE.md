# Identity architecture — how `~/.ssh/config` and `~/.gitconfig` work together

Managing several GitHub accounts (personal + one per company/client) from one Mac.
The whole system rests on one idea: **independent questions, answered by different
files, all switched by the same thing — the folder a repo lives in.**

To add a new company, see **[ADDING_AN_IDENTITY.md](ADDING_AN_IDENTITY.md)**. This
doc explains *why* it's shaped the way it is.

## The questions

| Question | Meaning | Controlled by |
|---|---|---|
| **"Who does the server think I am?"** | *Authentication* — which account may push/pull | the **SSH key** offered → `~/.ssh/config`, or git's `core.sshCommand` |
| **"Whose name is on the commit?"** | *Authorship* — the `Author:` stamped into history | `user.name` / `user.email` → `~/.gitconfig`, or an `includeIf` |
| **"Who does the *API* think I am?"** | The `gh` CLI's active account — which repos it can even see | `GH_CONFIG_DIR` → a per-identity `gh` config dir, chosen by a shell `cd` hook |

These are **independent** — you can authenticate as one account, author commits as
another, and have `gh` answer as a third. Almost every "wrong identity" bug is them
drifting apart (commit as personal, push over the company key, or vice-versa). The
system's only job is to **keep them aligned per context, automatically.**

The first two are git's, and git has native folder awareness (`includeIf`) to
resolve them. The third is not git's at all, and `gh` has no folder awareness —
which is why it needs its own mechanism to reach the same answer.

## What each file is responsible for

**`~/.ssh/config`** — the *transport* layer. It decides only **which key** is
offered to a host. It knows nothing about git authorship. It sets the **default**:

```sshconfig
Host github.com                 # personal is the default
    IdentityFile ~/.ssh/id_ed25519
    IdentityFile ~/.ssh/kernvex_id_ed25519   # same key, alt path on fresh machines
    IdentitiesOnly yes          # offer ONLY these, ignore whatever the agent holds
```

**`~/.gitconfig`** — the *git* layer. It sets your **authorship** (`user.email`),
and it can **override the key per-repo** via `core.sshCommand`. That override is
the lever that lets git ignore `~/.ssh/config` when a repo needs a different key.

## How they cooperate — a push, traced

**Personal repo** (anywhere *outside* a client folder):

1. Git has no `core.sshCommand` here → it runs plain `ssh`.
2. `ssh` reads `~/.ssh/config` → `Host github.com` → offers the personal key → **auth = personal**.
3. Authorship = global `~/.gitconfig` `[user]` → **personal email**. ✅ aligned.

**Company repo** (under a client folder, e.g. `~/Documents/Projects/Acme/`):

1. A git `includeIf` on that folder fires and sets **both** at once:
   - `user.email = awhite@acme.com` → **authorship = company**.
   - `core.sshCommand = ssh -F /dev/null -i ~/.ssh/acme_aw` → git runs *this* ssh.
2. `-F /dev/null` makes that ssh **ignore `~/.ssh/config` entirely** (so the personal
   key can't be offered), and `-i acme_aw` offers only the company key → **auth = company**. ✅ aligned.

So the **folder is the single switch** that flips authorship *and* the key together.
Put a repo in the client folder → it's company in both senses; anywhere else →
personal. `-F /dev/null` is what stops the two layers from fighting: git's override
wins cleanly instead of both keys being offered to the server.

### The third layer — `gh`, which has no folder awareness

Everything above is git resolving *its own* config, so `includeIf` can key on the
repo's path. The `gh` CLI never consults git config. It keeps **one active account
per host** in its own config file, and that account is a global mode — `gh auth
switch` flips it for every directory at once.

That makes `gh` the one place where the folder switch does not come for free, and
its failure is the nastiest in the system:

> A wrong-account `gh` **fails silently**. GitHub reports private or internal repos
> you can't see as `Could not resolve to a Repository` — not as an auth error. The
> work simply appears not to exist, which reads as "wrong URL", not "wrong identity".

The fix keeps the same shape as the git layers: instead of one config with a
switchable account, give **each identity its own `gh` config dir**, and let the
folder select it. `GH_CONFIG_DIR` points `gh` at a separate account store, so two
identities can never shadow each other — there is no shared mode to leave flipped.

Selection is a shell `cd` hook rather than a git mechanism, because `gh` is
invoked by the shell, not by git. That has one consequence worth stating plainly:
**the hook must exist in every shell, including non-interactive ones.** A script,
a GUI-launched tool or an agent's tool shell that misses the hook runs unrouted,
and unrouted means personal — silently, per the warning above.

**The `.inc` bridges the two layers.** HTTPS remotes take a second auth path that
`core.sshCommand` does not cover: git asks a **credential helper**, and the public
`~/.gitconfig` points that at `gh auth git-credential` — which resolves via
`GH_CONFIG_DIR`, i.e. by *shell*, not by folder. So a per-identity `.inc` pins the
helper to that identity's config dir. That pin is what drags `gh`'s shell-scoped
answer back under the folder switch, restoring the invariant for contexts that
never run your shell config at all.

### Why `includeIf` lives in a file included *last*

Git reads config top-to-bottom, and later values win. The personal `[user]` sits in
`~/.gitconfig`; the company `includeIf` must be evaluated *after* it or the personal
email would override the company one. So `~/.gitconfig` ends with:

```gitconfig
[include]
    path = ~/.config/git/local.inc     # evaluated last → its identities override personal
```

`local.inc` holds the `includeIf` blocks. A repo outside every client folder matches
no `includeIf`, so personal stands.

## Public vs. private — the data strategy

**Rule:** secrets are encrypted and/or private; benign-but-*identity-revealing*
config is untracked-local; only shared, non-revealing config is public. Three tiers:

| Tier | What lives here | Examples |
|---|---|---|
| 🟢 **Public** (`dotfiles` repo) | Shared, no secrets, reveals no client relationships | `~/.ssh/config` (key *paths*, never keys); `~/.gitconfig` (personal identity + a **generic** `[include] local.inc`, and the generic `gh auth git-credential` helper) |
| 🟡 **Generated, machine-local** (in `$HOME`, in no repo) | Benign but reveals *which* clients you work with, or is machine-specific | `~/.config/git/local.inc` (the `includeIf` folder→identity map); `~/.config/git/<slug>.inc` (per-identity email, key path, pinned credential helper); `~/.config/fish/conf.d/identity-routing.fish` + `~/.config/zsh/identity-routing.zsh` (the folder→per-CLI config-dir map) |
| 🔴 **Private** | The data 🟡 is generated from, and actual secrets | a **private** repo holding one data file per identity **plus** `ansible-vault` ciphertext for every non-personal key; live private keys `~/.ssh/*`; `~/.config/gh-<slug>/` and the other per-identity CLI config dirs (OAuth tokens — never in any repo). Personal is the one exception: a public repo whose key is encrypted, because it must be reachable *before* you can clone anything private |

The subtle trap this guards against: **`~/.gitconfig` is a stow symlink into the
*public* `dotfiles` repo**, so `git config --global …` writes to a public file.
That's fine for your personal identity (already public) but would leak company
routing. Hence company `includeIf` blocks live in 🟡 `~/.config/git/local.inc`, and
the public gitconfig carries only the generic `[include]` of it. The public repo
never learns which companies you work with; that fact lives only on your disk and
in the private identity repo.

The CLI hooks repeat that split exactly, and for the same reason:
`~/.config/fish/config.fish` is also a stow symlink into the public repo, while
`conf.d/` is a real, untracked directory — so the folder→identity map goes in
`conf.d/`, never in `config.fish`. The zsh twin is sourced from `~/.zshenv` rather
than `~/.zshrc`, because `.zshrc` is skipped for non-interactive zsh and an
unrouted shell falls back to personal.

> **One thing outranks all of it:** an exported `GH_TOKEN` / `GITHUB_TOKEN` beats
> `GH_CONFIG_DIR` outright. A token in your public shell config is a global
> override that silently defeats every folder switch above.

## Why it all survives a new machine

- 🟢 returns via `./install` (GNU stow) — public, no secrets.
- 🔴 the personal key returns from this repo (encrypted, the bootstrap exception);
  every other key returns by cloning the private identity repo and decrypting its
  vaults, which that repo's own restore command drives.
- 🟡 is **regenerated**, not restored: it is output of the 🔴 data. Without access
  to that repo it can still be rebuilt by hand from
  [ADDING_AN_IDENTITY.md](ADDING_AN_IDENTITY.md), which is why that runbook is
  deliberately kept working rather than reduced to a pointer.
- The CLI accounts themselves don't restore from anything: 🔴 tokens are not
  backed up by design. You re-run `auth login` once per identity per CLI, against
  that identity's own config dir.

Net effect: public repos are safe to be public, secrets sit behind private access
*and* a passphrase, and the "who am I here" wiring reassembles from data — no
single leak exposes a key **or** a client relationship.

### The cost this used to carry

The folder→identity map was written in **three** places — the `includeIf` in
`local.inc` and the two shell hooks — with a per-CLI config dir alongside each.
Nothing checked them against each other, and drift showed up only as the personal
account quietly answering in whichever shell was missed.

That is now resolved by generating all of 🟡 from a single data file per identity,
and by shipping a **checker** rather than only a generator. The checker asserts
routing in both directions: that work folders resolve to their identity, *and*
that everything outside them resolves to personal. The second half matters more
than it looks — the default is the case nobody inspects, and every failure in this
system is silent.
