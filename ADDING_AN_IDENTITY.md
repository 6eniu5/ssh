# Adding a git / SSH identity

How to add a new company or client identity so its repos automatically use the
right SSH key, the right commit name/email **and** the right GitHub account for
the `gh` CLI — while everything else stays personal. For *why* it's shaped this
way, read **[ARCHITECTURE.md](ARCHITECTURE.md)** first.

## The model (read once)

Routing is **by folder**, not by remote URL:

- `~/.ssh/config` makes **personal** (`~/.ssh/id_ed25519` → your personal GitHub)
  the default for `github.com`. Nothing else is forced there.
- Each extra identity owns a **folder** (e.g. `~/Documents/Projects/<Client>/`).
  A git `includeIf` on that folder sets, for every repo inside it, both the
  commit identity (`user.name`/`user.email`) and `core.sshCommand` (that
  identity's key). Clone a company repo into its folder → it just works.
- The `gh` CLI has **no** folder awareness, so it needs its own mechanism to
  reach the same result: a per-identity config dir chosen by a shell `cd` hook
  (Step 3). Same principle — the folder is the only switch.
- Each identity's private key is stored **encrypted** (`ansible-vault`) in its
  own repo, named by the convention **`ssh-<initials>`**:

  | repo | visibility | identity | key restored to |
  |---|---|---|---|
  | `ssh` | **public** | personal, bootstrap | `~/.ssh/id_ed25519` |
  | `ssh-<initials>` | **private** | one company/client | `~/.ssh/<key>` |

> **Golden rule:** never add `Host * IdentityFile …` to `~/.ssh/config`. That
> forces one key onto every host and makes pushes authenticate as the wrong
> account (the original bug this whole scheme fixed).

---

## One-time base (already done on this machine)

`~/.ssh/config`:

```sshconfig
Host *
    AddKeysToAgent yes
Host github.com                 # default = personal
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentityFile ~/.ssh/6eniu5_id_ed25519   # same key, path used on fresh machines
    IdentitiesOnly yes
```

Global `~/.gitconfig` `user.*` = your personal identity, and it ends with
`[include] path = ~/.config/git/local.inc` — an untracked, machine-local file
where per-identity `includeIf` blocks live (so company routing never lands in the
public dotfiles repo). Everything below is the **per-identity** part you repeat.

---

## Add an identity (repeatable)

### Step 0 — pick the values

```bash
INITIALS="aw"                                   # → private repo ssh-aw, inc file aw.inc
FULL_NAME="Alice Wu"                             # commit author name for this identity
EMAIL="alice@acme.com"                           # commit email for this identity
GH_OWNER="kernvex"                               # account that hosts the private vault repo
WORK_DIR="$HOME/Documents/Projects/Acme"         # clone this client's repos under here
KEY="$HOME/.ssh/acme_aw"                          # SSH private key for this identity
GH_CONFIG_DIR="$HOME/.config/gh-acme"            # this identity's own gh account store
VAULT_REPO="ssh-${INITIALS}"                      # e.g. ssh-aw
VAULT_DIR="$HOME/Documents/Projects/setup/${VAULT_REPO}"
```

> **`GH_OWNER` is a login, not a display label.** `~/.config/gh/hosts.yml` may
> show an older account name; the value that matters is what
> `gh api user --jq .login` reports. Check it rather than reading it off the
> config, or `gh repo create` fails with a confusing ownership error.

### Step 1 — the SSH key

Reuse an existing key, or generate one and add its **public** half to that
GitHub account (Settings → SSH keys):

```bash
[ -f "$KEY" ] || ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY"   # generate if missing
pbcopy < "${KEY}.pub"    # then paste into github.com → the client account → SSH keys
```

Confirm which account it authenticates as:

```bash
ssh -F /dev/null -i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -T git@github.com
# → "Hi <client-username>!"
```

### Step 2 — routing (folder → identity)

```bash
mkdir -p "$WORK_DIR" ~/.config/git

cat > ~/.config/git/${INITIALS}.inc <<EOF
[user]
    name = ${FULL_NAME}
    email = ${EMAIL}
[core]
    sshCommand = ssh -F /dev/null -o UserKnownHostsFile=~/.ssh/known_hosts -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i ${KEY}
EOF

# Map the folder → that identity. Add it to the machine-local include, NOT via
# `git config --global` — that writes into ~/.gitconfig, which is public via
# dotfiles. ~/.gitconfig already ends with `[include] path = ~/.config/git/local.inc`.
# Trailing slash = "this folder and everything under it".
cat >> ~/.config/git/local.inc <<EOF

[includeIf "gitdir:${WORK_DIR}/"]
    path = ~/.config/git/${INITIALS}.inc
EOF
```

`-F /dev/null` isolates the key so the personal `github.com` identity can't be
offered first. `local.inc` is included **last** from `~/.gitconfig`, so a
matched identity's email/key override the personal defaults for its folder.

This covers **SSH remotes**. The `.inc` gets one more block in Step 3, for HTTPS
remotes and for the `gh` CLI.

> **Company not on github.com?** (GitHub Enterprise `github.<co>.com`, GitLab,
> Bitbucket) — same steps, nothing extra in `~/.ssh/config`. The folder's
> `core.sshCommand` carries the key to *any* host, and `-F /dev/null` +
> `StrictHostKeyChecking=accept-new` handle the unknown host on first connect.
> Just register the public key on that host, clone its URL into `$WORK_DIR`, and
> in the Step 1 auth test swap `git@github.com` for the company host
> (e.g. `git@github.acme.com`).

### Step 3 — routing the `gh` CLI (folder → GitHub account)

Step 2 routes `git`. It does **not** route `gh`, and `gh` is where this scheme
most often looks like it's working when it isn't:

> **A wrong-account `gh` fails silently.** GitHub answers queries about private
> or internal repos you can't see with `Could not resolve to a Repository`, not
> with an auth error. Every work repo simply appears not to exist. If `gh` says
> a repo you can see in the browser doesn't exist, suspect the account before
> anything else.

`gh` keeps **one active account per host** in its config and has no folder
awareness, so `gh auth switch` is a global mode you have to remember to flip.
Instead give each identity **its own config dir** and let the folder select it,
matching the git model: `GH_CONFIG_DIR` points `gh` at a separate account store,
so two identities can never shadow each other.

Selection is a `cd` hook, so it must exist in **both** shells:

```fish
# ~/.config/fish/conf.d/gh-identity.fish   (create if missing; else add a case)
function __gh_identity_apply --on-variable PWD
    switch $PWD
        case "$HOME/Documents/Projects/Acme" "$HOME/Documents/Projects/Acme/*"
            set -gx GH_CONFIG_DIR "$HOME/.config/gh-acme"
        # ↑ one case branch per identity, above the catch-all
        case '*'
            set -e GH_CONFIG_DIR
    end
end

# --on-variable only fires on CHANGE, so apply once for the shell's initial cwd.
__gh_identity_apply
```

```zsh
# ~/.config/zsh/gh-identity.zsh   (the twin — keep the two in sync)
__gh_identity_apply() {
  case "$PWD" in
    "$HOME/Documents/Projects/Acme"|"$HOME/Documents/Projects/Acme"/*)
      export GH_CONFIG_DIR="$HOME/.config/gh-acme" ;;
    *)
      unset GH_CONFIG_DIR ;;
  esac
}

autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd __gh_identity_apply
__gh_identity_apply   # chpwd only fires on CHANGE
```

Source the zsh half from **`~/.zshenv`**, not `~/.zshrc`:

```sh
[ -r "$HOME/.config/zsh/gh-identity.zsh" ] && . "$HOME/.config/zsh/gh-identity.zsh"
```

> **Why `.zshenv`.** fish sources everything in `conf.d` for *every* fish shell,
> interactive or not. zsh does not: `~/.zshrc` is skipped for `zsh -c`, so
> scripts, GUI-launched tools and agent tooling would all run unrouted — and an
> unrouted shell falls back to the personal account, silently. `.zshenv` is read
> by every zsh.

Then log this identity in against its own dir:

```bash
env GH_CONFIG_DIR="$GH_CONFIG_DIR" gh auth login --hostname github.com --git-protocol ssh
```

> **An exported `GH_TOKEN` / `GITHUB_TOKEN` outranks `GH_CONFIG_DIR` entirely**
> and defeats the whole scheme. If your shell config exports one (a token-refresh
> helper, a CI shim), it must not be active for these folders.

Finally, **HTTPS remotes**. They take a second auth path that Step 2's
`core.sshCommand` does not cover: git asks a credential helper, and the public
`~/.gitconfig` points that at `gh auth git-credential`, which resolves via
`GH_CONFIG_DIR` — i.e. by *shell*, not by folder. Pin it in the `.inc` so the
answer depends on the repo's location only:

```bash
cat >> ~/.config/git/${INITIALS}.inc <<EOF

# The empty helper resets the inherited personal one; without the reset git
# appends and the personal helper is still tried first.
[credential "https://github.com"]
    helper =
    helper = "!GH_CONFIG_DIR=${GH_CONFIG_DIR} $(command -v gh) auth git-credential"
EOF
```

The absolute path to `gh` is deliberate — the helper can run somewhere Homebrew
isn't on `PATH`.

### Step 4 — the private vault repo (scaffold from an existing one)

```bash
gh repo create "${GH_OWNER}/${VAULT_REPO}" --private \
  -d "Encrypted SSH key vault — ${FULL_NAME} identity (ssh-{initials} convention)"

mkdir -p "$VAULT_DIR" && cd "$VAULT_DIR"
# reuse the proven scaffold from any vault repo you already have:
TEMPLATE="$HOME/Documents/Projects/setup/ssh-<existing-initials>"
cp "$TEMPLATE/.gitignore" "$TEMPLATE/decrypt_ssh_vault.sh" .
# then edit decrypt_ssh_vault.sh's default paths + the README for THIS identity.
git init -q -b main
git remote add origin "git@github.com:${GH_OWNER}/${VAULT_REPO}.git"
```

`.gitignore` is a whitelist — only `*.vault`, the README, and the script are ever
committable, so a raw key can't slip in.

> **Run `gh repo create` from outside `$WORK_DIR`.** The vault repo belongs to
> your personal account, and inside a work folder Step 3 has already switched
> `gh` to the client's — which rejects it: *"\<client-user\> cannot create a
> repository for \<your-account\>"*. That error is the routing working. Any
> personal `gh` admin command has the same constraint. `$VAULT_DIR` sits under
> `~/Documents/Projects/setup/`, outside every work folder, so the steps below
> are already in the right place.

### Step 5 — encrypt the key (interactive — you type the passphrase)

```bash
ansible-vault encrypt "$KEY" --output "$VAULT_DIR/$(basename "$KEY").vault"
```

Use a **strong passphrase, separate per identity**. `--output` leaves the live
key untouched.

### Step 6 — commit + push the vault

```bash
cd "$VAULT_DIR"
git add -A
git status --short           # sanity: ONLY *.vault + docs, never the raw key
git commit -m "add $(basename "$KEY").vault (ansible-vault AES256)"
git push -u origin main       # pushes as personal (this dir is outside any client folder)
```

### Step 7 — verify

Do this **from a fresh shell**. The `gh` hooks are applied at shell startup, so
a shell older than the config you just wrote will not have them.

```bash
# commit identity + key resolve inside the client folder:
git -C "$WORK_DIR" init -q 2>/dev/null; \
  git -C "$WORK_DIR" config user.email; \
  git -C "$WORK_DIR" config core.sshCommand
# real auth to a client repo (after cloning one into $WORK_DIR):
#   git -C "$WORK_DIR/<repo>" ls-remote origin HEAD   # succeeds as the client user
```

`gh` and the credential helper, checked as a pair — the point is that both
answers flip on the folder alone:

```bash
cd "$WORK_DIR/<repo>"; gh api user --jq .login; git config user.email   # → client
cd ~;                  gh api user --jq .login; git config user.email   # → personal
```

Run those in **each** shell you use. A missing branch in one of the two hook
files shows up only there, and only as the personal account answering.

```bash
# The HTTPS path, with the shell hook deliberately defeated — this proves the
# pinned credential helper works for contexts that never run your shell config:
env -u GH_CONFIG_DIR GIT_TERMINAL_PROMPT=0 git ls-remote <client-https-url> HEAD
```

Prompting for a password, or failing where the SSH remote succeeded, means the
`[credential]` block from Step 3 is missing or not being matched.

---

## Checklist

- [ ] Public key added to the client's GitHub account, `ssh -i` greets the right user
- [ ] `~/.config/git/<initials>.inc` created (user + core.sshCommand)
- [ ] `includeIf "gitdir:<folder>/"` added to `~/.config/git/local.inc` (**not** `~/.gitconfig`)
- [ ] A case branch for the folder in **both** `gh-identity.fish` and `gh-identity.zsh`
- [ ] The zsh hook sourced from `~/.zshenv` (not `~/.zshrc`)
- [ ] `gh auth login` done against this identity's `GH_CONFIG_DIR`
- [ ] `[credential "https://github.com"]` block pinned in the `.inc`, empty `helper =` first
- [ ] Private `ssh-<initials>` repo created + scaffolded
- [ ] Key encrypted with a strong, separate passphrase; `git status` shows only `*.vault`
- [ ] Vault committed + pushed
- [ ] From a fresh shell, in **each** shell: a repo under the folder resolves the
      right identity, key **and** `gh` account; `~` still resolves personal

## What changed, where

| Location | Purpose |
|---|---|
| `~/.ssh/config` | personal default only — **never** touched per identity |
| `~/.config/git/<initials>.inc` | this identity's commit name/email, `core.sshCommand`, pinned credential helper |
| `~/.config/git/local.inc` | untracked; the `includeIf` blocks binding folders → `.inc`s |
| `~/.gitconfig` (public) | personal identity + `[include] local.inc` — no company specifics |
| `~/.config/fish/conf.d/gh-identity.fish` | untracked; folder → `GH_CONFIG_DIR` (fish) |
| `~/.config/zsh/gh-identity.zsh` + a `~/.zshenv` source line | the same for zsh, including non-interactive |
| `~/.config/gh-<name>/` | this identity's `gh` account store, separate from the personal one |
| `ssh-<initials>` repo (private) | the encrypted key + its decrypt script |

> **Known cost:** the folder → identity map now lives in **three** places — the
> `includeIf` in `local.inc` and the two shell hooks. Drift between them fails
> silently, in whichever shell was missed. Adding an identity means editing all
> three.

## Restoring on a new machine

1. Bootstrap **personal** from the public `ssh` repo (that key clones everything else).
2. For each identity: `git clone git@github.com:<owner>/ssh-<initials>` → `./decrypt_ssh_vault.sh`.
3. Recreate the `.inc` + `includeIf` (Step 2) and both `gh` hooks + the `.zshenv`
   line (Step 3), then `gh auth login` per identity. Folders route automatically.

The key alone is not the identity: restore it without the routing files and work
repos quietly authenticate as personal, reporting private repos as nonexistent.
