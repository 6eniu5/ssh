# Identity architecture — how `~/.ssh/config` and `~/.gitconfig` work together

Managing several GitHub accounts (personal + one per company/client) from one Mac.
The whole system rests on one idea: **two independent questions, answered by two
different files, both switched by the same thing — the folder a repo lives in.**

To add a new company, see **[ADDING_AN_IDENTITY.md](ADDING_AN_IDENTITY.md)**. This
doc explains *why* it's shaped the way it is.

## The two questions

| Question | Meaning | Controlled by |
|---|---|---|
| **"Who does the server think I am?"** | *Authentication* — which account may push/pull | the **SSH key** offered → `~/.ssh/config`, or git's `core.sshCommand` |
| **"Whose name is on the commit?"** | *Authorship* — the `Author:` stamped into history | `user.name` / `user.email` → `~/.gitconfig`, or an `includeIf` |

These are **independent** — you can authenticate as one account and author commits
as another. Almost every "wrong identity" bug is these two drifting apart (commit
as personal, push over the company key, or vice-versa). The system's only job is
to **keep them aligned per context, automatically.**

## What each file is responsible for

**`~/.ssh/config`** — the *transport* layer. It decides only **which key** is
offered to a host. It knows nothing about git authorship. It sets the **default**:

```sshconfig
Host github.com                 # personal is the default
    IdentityFile ~/.ssh/id_ed25519
    IdentityFile ~/.ssh/6eniu5_id_ed25519   # same key, alt path on fresh machines
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
| 🟢 **Public** (`dotfiles` repo) | Shared, no secrets, reveals no client relationships | `~/.ssh/config` (key *paths*, never keys); `~/.gitconfig` (personal identity + a **generic** `[include] local.inc`) |
| 🟡 **Untracked local** (in `$HOME`, in no repo) | Benign but reveals *which* clients you work with, or is machine-specific | `~/.config/git/local.inc` (the `includeIf` folder→identity map); `~/.config/git/<initials>.inc` (per-identity email + key path) |
| 🔴 **Private / encrypted** | Actual secrets | private keys `~/.ssh/*`; `ansible-vault` ciphertext in **private** `ssh-<initials>` repos (personal is the one exception — a public repo, but its key is encrypted for bootstrap) |

The subtle trap this guards against: **`~/.gitconfig` is a stow symlink into the
*public* `dotfiles` repo**, so `git config --global …` writes to a public file.
That's fine for your personal identity (already public) but would leak company
routing. Hence company `includeIf` blocks live in 🟡 `~/.config/git/local.inc`, and
the public gitconfig carries only the generic `[include]` of it. The public repo
never learns which companies you work with; that fact lives only on your disk and
in the private `ssh-<initials>` repo.

## Why it all survives a new machine

- 🟢 returns via `./install` (GNU stow) — public, no secrets.
- 🔴 keys return by cloning the vault repos + `decrypt_ssh_vault.sh` (personal from
  the public `ssh` repo, then each private `ssh-<initials>`).
- 🟡 `local.inc` + `<initials>.inc` are recreated by following
  [ADDING_AN_IDENTITY.md](ADDING_AN_IDENTITY.md) — a few non-secret lines, so a
  runbook is enough; they never need to be tracked.

Net effect: public repos are safe to be public, secrets sit behind private access
*and* a passphrase, and the "who am I here" wiring reassembles from a documented
runbook — no single leak exposes a key **or** a client relationship.
