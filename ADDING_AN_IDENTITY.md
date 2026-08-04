# Adding a git / SSH identity

How to make a new company or client identity route automatically: the right SSH
key, the right commit name and email, and the right account for every CLI you use
there — while everything else stays personal. For *why* it's shaped this way,
read **[ARCHITECTURE.md](ARCHITECTURE.md)** first.

## Two paths, and which one you want

**The generated path.** On a machine that has the private `identity` repo, an
identity is one data file and one command:

```bash
identity add --slug acme --name "Alice Wu" --email alice@acme.com \
             --dir ~/work/Acme --key ~/.ssh/acme_aw --tools "gh gcloud"
identity check --deep
```

Everything below is then generated, and `identity check` verifies it. That repo
is private because the map of which folder belongs to which client is exactly the
fact this public repo must never learn.

**The by-hand path — the rest of this document.** It is the fallback, and it is
deliberately kept working: on a fresh machine you may have the personal key from
this repo and nothing else, and you need to be able to rebuild routing without
the private repo. It is also the specification the generator implements.

> This document describes **what must be true**. The private repo owns the exact
> bytes. If the two ever disagree, the invariants here are the intent.

## The model (read once)

Routing is **by folder**, not by remote URL, not by shell, not by which account
you last switched to:

- `~/.ssh/config` makes **personal** the default for `github.com`. Nothing else
  is forced there.
- Each extra identity owns a **folder**. A git `includeIf` on that folder sets,
  for every repo inside it, the commit identity and `core.sshCommand`. Clone a
  company repo into its folder and it just works.
- **CLIs have no folder awareness at all.** `gh`, `gcloud`, `az` and `aws` each
  keep one active account in their own config, switched globally. They need a
  shell `cd` hook pointing each at a per-identity config directory, so the folder
  reaches them too.
- The private key is stored **encrypted** (`ansible-vault`) in a private repo,
  never in this one — with one deliberate exception, the personal bootstrap key
  in this repo, which has to be reachable before you can clone anything private.

> **Golden rule:** never add `Host * IdentityFile …` to `~/.ssh/config`. That
> forces one key onto every host and makes pushes authenticate as the wrong
> account — the original bug this whole scheme fixed.

## The invariants

An identity is correctly routed when **all** of these hold. Anything that
produces them is a valid implementation.

| # | Invariant | Where it lives |
|---|---|---|
| 1 | Inside the folder, `user.name` / `user.email` are the identity's | `~/.config/git/<slug>.inc` |
| 2 | Inside the folder, `core.sshCommand` offers only that identity's key | same file, `-F /dev/null -o IdentitiesOnly=yes` |
| 3 | The folder is bound to that file | `includeIf "gitdir:<folder>/"` in `~/.config/git/local.inc` |
| 4 | Inside the folder, every routed CLI points at that identity's config dir | a `cd` hook, in **both** shells |
| 5 | HTTPS remotes resolve the same credential regardless of shell | a `[credential]` block in the `.inc` |
| 6 | **Outside** every such folder, all of the above resolve to personal | the catch-all branch, plus nothing in `~/.gitconfig` |
| 7 | The key exists encrypted somewhere private, and only encrypted | a private repo with a whitelist `.gitignore` |

Invariant 6 is the one people forget to check. The default is what nobody
inspects, and a wrong default is silent.

---

## One-time base (already done on this machine)

`~/.ssh/config`:

```sshconfig
Host *
    AddKeysToAgent yes
Host github.com                 # default = personal
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentityFile ~/.ssh/kernvex_id_ed25519   # same key, path used on fresh machines
    IdentitiesOnly yes
```

Global `~/.gitconfig` `user.*` is your personal identity, and it ends with
`[include] path = ~/.config/git/local.inc` — a machine-local file where per-identity
`includeIf` blocks live, so company routing never lands in the public dotfiles repo.

---

## Add an identity by hand

### Step 0 — pick the values

```bash
SLUG="acme"                                      # full company name, not initials
FULL_NAME="Alice Wu"
EMAIL="alice@acme.com"
WORK_DIR="$HOME/work/Acme"                       # clone this client's repos under here
KEY="$HOME/.ssh/acme_aw"
GH_CONFIG_DIR="$HOME/.config/gh-${SLUG}"         # this identity's own gh account store
```

> **Slug is the company, not initials.** Every derived name uses it — the `.inc`,
> and one config dir per CLI. `~/.config/gh-acme` identifies itself in an
> environment dump; `~/.config/gh-aw` does not. Two clients can also share
> initials, and a persona can change while the company does not.

> **`GH_OWNER` is a login, not a display label.** `~/.config/gh/hosts.yml` may
> show an older account name; what matters is what `gh api user --jq .login`
> reports. Read it rather than the config, or `gh repo create` fails with a
> confusing ownership error.

### Step 1 — the SSH key

```bash
[ -f "$KEY" ] || ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY"
pbcopy < "${KEY}.pub"    # paste into the client's GitHub account → SSH keys
```

Confirm which account it authenticates as:

```bash
ssh -F /dev/null -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -T git@github.com
# → "Hi <client-username>!"
```

### Step 2 — git routing (invariants 1–3)

```bash
mkdir -p "$WORK_DIR" ~/.config/git

cat > ~/.config/git/${SLUG}.inc <<EOF
[user]
    name = ${FULL_NAME}
    email = ${EMAIL}
[core]
    sshCommand = ssh -F /dev/null -o UserKnownHostsFile=~/.ssh/known_hosts -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i ${KEY}
EOF

# Bind the folder. Add it to the machine-local include, NOT via `git config
# --global` — that writes into ~/.gitconfig, which is public via dotfiles.
# Trailing slash = "this folder and everything under it".
cat >> ~/.config/git/local.inc <<EOF

[includeIf "gitdir:${WORK_DIR}/"]
    path = ~/.config/git/${SLUG}.inc
EOF
```

`-F /dev/null` isolates the key so the personal `github.com` identity can't be
offered first. `local.inc` is included **last** from `~/.gitconfig`, so a matched
identity overrides the personal defaults for its folder.

> **Company not on github.com?** (GitHub Enterprise, GitLab, Bitbucket) — same
> steps, nothing extra in `~/.ssh/config`. The folder's `core.sshCommand` carries
> the key to *any* host, and `-F /dev/null` + `StrictHostKeyChecking=accept-new`
> handle the unknown host on first connect. Register the public key there, clone
> its URL into `$WORK_DIR`, and swap the host in the Step 1 test.

### Step 3 — CLI routing (invariant 4)

Step 2 routes `git`. It does **not** route any CLI, and this is where the scheme
most often looks like it's working when it isn't:

> **A wrong-account `gh` fails silently.** GitHub answers queries about private
> or internal repos you can't see with `Could not resolve to a Repository`, not
> with an auth error. Every work repo simply appears not to exist. If `gh` says a
> repo you can see in the browser doesn't exist, suspect the account first.

Each CLI keeps **one active account** and has no folder awareness, so its own
"switch account" command is a global mode you must remember to flip. Instead give
each identity **its own config dir** and let the folder select it:

| CLI | Variable | Note |
|---|---|---|
| `gh` | `GH_CONFIG_DIR=~/.config/gh-<slug>` | |
| `gcloud` | `CLOUDSDK_CONFIG=~/.config/gcloud-<slug>` | isolates credentials, not just the active config |
| `az` | `AZURE_CONFIG_DIR=~/.config/azure-<slug>` | |
| `aws` | `AWS_CONFIG_FILE` **and** `AWS_SHARED_CREDENTIALS_FILE` under `~/.config/aws-<slug>/` | weaker: the SSO/CLI caches under `~/.aws` are **not** redirected |

Selection is a `cd` hook, so it must exist in **both** shells:

```fish
# ~/.config/fish/conf.d/identity-routing.fish
function __identity_routing_apply --on-variable PWD
    switch $PWD
        case "$HOME/work/Acme" "$HOME/work/Acme/*"
            set -gx GH_CONFIG_DIR "$HOME/.config/gh-acme"
            set -gx CLOUDSDK_CONFIG "$HOME/.config/gcloud-acme"
        # ↑ one case branch per identity, above the catch-all
        case '*'
            set -e GH_CONFIG_DIR
            set -e CLOUDSDK_CONFIG
    end
end

# --on-variable only fires on CHANGE, so apply once for the shell's initial cwd.
__identity_routing_apply
```

```zsh
# ~/.config/zsh/identity-routing.zsh   (the twin — keep the two in sync)
__identity_routing_apply() {
  case "$PWD" in
    "$HOME/work/Acme"|"$HOME/work/Acme"/*)
      export GH_CONFIG_DIR="$HOME/.config/gh-acme"
      export CLOUDSDK_CONFIG="$HOME/.config/gcloud-acme" ;;
    *)
      unset GH_CONFIG_DIR
      unset CLOUDSDK_CONFIG ;;
  esac
}

autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd __identity_routing_apply
__identity_routing_apply   # chpwd only fires on CHANGE
```

> **The catch-all must clear every variable any identity uses, not just this
> one's.** Otherwise a variable set inside one client's folder survives a `cd`
> into another's, and that folder is then half-routed — the failure this design
> exists to prevent.

Source the zsh half from **`~/.zshenv`**, not `~/.zshrc`:

```sh
[ -r "$HOME/.config/zsh/identity-routing.zsh" ] && . "$HOME/.config/zsh/identity-routing.zsh"
```

> **Why `.zshenv`.** fish sources everything in `conf.d` for *every* fish shell,
> interactive or not. zsh does not: `~/.zshrc` is skipped for `zsh -c`, so
> scripts, GUI-launched tools and coding agents' tool shells would all run
> unrouted — and an unrouted shell falls back to personal, silently. `.zshenv`
> is read by every zsh.

Then log this identity in against its own dir:

```bash
env GH_CONFIG_DIR="$GH_CONFIG_DIR" gh auth login --hostname github.com --git-protocol ssh
# and per CLI, e.g.:  env CLOUDSDK_CONFIG=~/.config/gcloud-acme gcloud auth login
```

> **An exported `GH_TOKEN` / `GITHUB_TOKEN` outranks `GH_CONFIG_DIR` entirely**
> and defeats the whole scheme; `GOOGLE_APPLICATION_CREDENTIALS` does the same to
> gcloud's application-default credentials. If your shell config exports one (a
> token-refresh helper, a CI shim), it must not be active for these folders.

### Step 4 — HTTPS remotes (invariant 5)

HTTPS takes a second auth path that Step 2's `core.sshCommand` does not cover:
git asks a credential helper, and the public `~/.gitconfig` points that at
`gh auth git-credential`, which resolves via `GH_CONFIG_DIR` — i.e. by *shell*,
not by folder. A GUI client or a scheduled job has no hook and would reach for
the personal token. Pin it in the `.inc`:

```bash
cat >> ~/.config/git/${SLUG}.inc <<EOF

# The empty helper RESETS the inherited personal one; without the reset git
# appends and the personal helper is still tried first.
[credential "https://github.com"]
    helper =
    helper = "!GH_CONFIG_DIR=${GH_CONFIG_DIR} $(command -v gh) auth git-credential"
EOF
```

The absolute path to `gh` is deliberate — the helper can run somewhere Homebrew
isn't on `PATH`.

### Step 5 — store the key encrypted (invariant 7)

The key belongs in your **private** identity repo, alongside the data that routes
it. One repo per identity is not needed: the routing files are global and can't
live in a per-identity repo anyway, and each vault keeps its own passphrase
regardless of which private repo holds it.

```bash
ansible-vault encrypt "$KEY" --output <private-repo>/vaults/$(basename "$KEY").vault
git -C <private-repo> status --short   # sanity: ONLY *.vault, never the raw key
```

Use a **strong passphrase, separate per identity**, so one secret never unlocks
two clients. `--output` leaves the live key untouched. That repo's `.gitignore`
should be a **whitelist**, so a raw key cannot be committed by accident.

> **Run personal `gh` admin commands from outside `$WORK_DIR`.** Inside a work
> folder Step 3 has already switched `gh` to the client's account, which will
> reject them: *"\<client-user\> cannot create a repository for \<your-account\>"*.
> That error is the routing working.

### Step 6 — verify

Do this **from a fresh shell**. The hooks are applied at shell startup, so a
shell older than the config you just wrote will not have them.

```bash
# Both answers must flip on the folder alone. Run in EACH shell you use —
# a missing branch in one hook file shows up only there, and only as the
# personal account quietly answering.
cd "$WORK_DIR/<repo>"; gh api user --jq .login; git config user.email   # → client
cd ~;                  gh api user --jq .login; git config user.email   # → personal
```

> **Probe from inside a repo, not the folder itself.** An `includeIf "gitdir:"`
> condition only fires within a repository, so testing the bare work folder
> reports the personal identity and looks like a failure when nothing is wrong.

```bash
# The HTTPS path, with the shell hook deliberately defeated — this proves the
# pinned credential helper works for contexts that never run your shell config:
env -u GH_CONFIG_DIR GIT_TERMINAL_PROMPT=0 git ls-remote <client-https-url> HEAD
```

Prompting for a password, or failing where the SSH remote succeeded, means the
`[credential]` block from Step 4 is missing or not being matched.

---

## Checklist

- [ ] Public key added to the client's GitHub account, `ssh -i` greets the right user
- [ ] `~/.config/git/<slug>.inc` created (user + `core.sshCommand`)
- [ ] `includeIf "gitdir:<folder>/"` added to `~/.config/git/local.inc` (**not** `~/.gitconfig`)
- [ ] A case branch for the folder in **both** hook files, and the catch-all clears **every** routed variable
- [ ] The zsh hook sourced from `~/.zshenv` (not `~/.zshrc`)
- [ ] `auth login` done against this identity's config dir, per CLI
- [ ] `[credential "https://github.com"]` pinned in the `.inc`, empty `helper =` first
- [ ] Key encrypted with a strong, separate passphrase, into a private repo whose `.gitignore` is a whitelist
- [ ] From a fresh shell, in **each** shell: a repo under the folder resolves the identity, and `~` resolves personal

## What changed, where

| Location | Purpose |
|---|---|
| `~/.ssh/config` | personal default only — **never** touched per identity |
| `~/.config/git/<slug>.inc` | commit identity, `core.sshCommand`, pinned credential helper |
| `~/.config/git/local.inc` | machine-local; the `includeIf` blocks binding folders → `.inc`s |
| `~/.config/fish/conf.d/identity-routing.fish` + `~/.config/zsh/identity-routing.zsh` | folder → per-CLI config dirs |
| `~/.gitconfig` (public) | personal identity + a generic `[include]` — no company specifics |
| private identity repo | the data these are generated from, and the encrypted keys |

> **The by-hand version of this is written in five places that nothing checks
> against each other.** That is why the generated path exists, and why it ships a
> checker rather than only a generator. If you are doing it by hand, the
> verification in Step 6 is not optional.

## Restoring on a new machine

1. Bootstrap **personal** from this repo — that key is what clones everything else.
2. Clone the private identity repo and run its restore, which decrypts the vaults
   and regenerates everything above. Or, without it, repeat Steps 2–4 by hand.
3. Re-run `auth login` once per identity per CLI. Those tokens are deliberately
   not backed up anywhere.
