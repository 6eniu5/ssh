# ssh repo (public)
This repo contains an encrypted payload for ~/.ssh/id_ed25519.
To decrypt on a target user:
- Install Ansible (provides ansible-vault)
- Run: ansible-vault decrypt ./id_ed25519.vault --output ~/.ssh/id_ed25519
- chmod 600 ~/.ssh/id_ed25519
- Ensure ~/.ssh/known_hosts includes github.com (ssh-keyscan)
