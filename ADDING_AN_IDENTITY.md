# Adding a git / SSH identity

How to add a new company or client identity so its repos automatically use the
right SSH key **and** the right commit name/email — while everything else stays
personal. This is the repeatable version of how `ssh-jw` was set up.

## The model (read once)

Routing is **by folder**, not by remote URL:

- `~/.ssh/config` makes **personal** (`~/.ssh/id_ed25519` → your personal GitHub)
  the default for `github.com`. Nothing else is forced there.
- Each extra identity owns a **folder** (e.g. `~/Documents/Projects/<Client>/`).
  A git `includeIf` on that folder sets, for every repo inside it, both the
  commit identity (`user.name`/`user.email`) and `core.sshCommand` (that
  identity's key). Clone a company repo into its folder → it just works.
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
    IdentitiesOnly yes
```

Global `~/.gitconfig` `user.*` = your personal identity. Everything below is the
**per-identity** part you repeat.

---

## Add an identity (repeatable)

### Step 0 — pick the values

```bash
INITIALS="aw"                                   # → private repo ssh-aw, inc file aw.inc
FULL_NAME="Alice Wu"                             # commit author name for this identity
EMAIL="alice@acme.com"                           # commit email for this identity
GH_OWNER="6eniu5"                                # account that hosts the private vault repo
WORK_DIR="$HOME/Documents/Projects/Acme"         # clone this client's repos under here
KEY="$HOME/.ssh/acme_aw"                          # SSH private key for this identity
VAULT_REPO="ssh-${INITIALS}"                      # e.g. ssh-aw
VAULT_DIR="$HOME/Documents/Projects/setup/${VAULT_REPO}"
```

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

# Trailing slash = "this folder and everything under it".
git config --global includeIf."gitdir:${WORK_DIR}/".path "~/.config/git/${INITIALS}.inc"
```

`-F /dev/null` isolates the key so the personal `github.com` identity can't be
offered first.

### Step 3 — the private vault repo (copy ssh-jw as the template)

```bash
gh repo create "${GH_OWNER}/${VAULT_REPO}" --private \
  -d "Encrypted SSH key vault — ${FULL_NAME} identity (ssh-{initials} convention)"

mkdir -p "$VAULT_DIR" && cd "$VAULT_DIR"
# reuse the proven scaffold from ssh-jw:
cp ~/Documents/Projects/setup/ssh-jw/.gitignore .
cp ~/Documents/Projects/setup/ssh-jw/decrypt_ssh_vault.sh .
# then edit decrypt_ssh_vault.sh's default paths and README for THIS identity.
git init -q -b main
git remote add origin "git@github.com:${GH_OWNER}/${VAULT_REPO}.git"
```

`.gitignore` is a whitelist — only `*.vault`, the README, and the script are ever
committable, so a raw key can't slip in.

### Step 4 — encrypt the key (interactive — you type the passphrase)

```bash
ansible-vault encrypt "$KEY" --output "$VAULT_DIR/$(basename "$KEY").vault"
```

Use a **strong passphrase, separate per identity**. `--output` leaves the live
key untouched.

### Step 5 — commit + push the vault

```bash
cd "$VAULT_DIR"
git add -A
git status --short           # sanity: ONLY *.vault + docs, never the raw key
git commit -m "add $(basename "$KEY").vault (ansible-vault AES256)"
git push -u origin main       # pushes as personal (this dir is outside any client folder)
```

### Step 6 — verify

```bash
# commit identity + key resolve inside the client folder:
git -C "$WORK_DIR" init -q 2>/dev/null; \
  git -C "$WORK_DIR" config user.email; \
  git -C "$WORK_DIR" config core.sshCommand
# real auth to a client repo (after cloning one into $WORK_DIR):
#   git -C "$WORK_DIR/<repo>" ls-remote origin HEAD   # succeeds as the client user
```

---

## Checklist

- [ ] Public key added to the client's GitHub account, `ssh -i` greets the right user
- [ ] `~/.config/git/<initials>.inc` created (user + core.sshCommand)
- [ ] `includeIf "gitdir:<folder>/"` added to `~/.gitconfig`
- [ ] Private `ssh-<initials>` repo created + scaffolded
- [ ] Key encrypted with a strong, separate passphrase; `git status` shows only `*.vault`
- [ ] Vault committed + pushed
- [ ] A repo under the folder resolves the right identity + key

## What changed, where

| Location | Purpose |
|---|---|
| `~/.ssh/config` | personal default only — **never** touched per identity |
| `~/.config/git/<initials>.inc` | this identity's commit name/email + `core.sshCommand` |
| `~/.gitconfig` `[includeIf]` | binds the folder to that `.inc` |
| `ssh-<initials>` repo (private) | the encrypted key + its decrypt script |

## Restoring on a new machine

1. Bootstrap **personal** from the public `ssh` repo (that key clones everything else).
2. For each identity: `git clone git@github.com:<owner>/ssh-<initials>` → `./decrypt_ssh_vault.sh`.
3. Recreate the `.inc` + `includeIf` (Step 2). Done — folders route automatically.
