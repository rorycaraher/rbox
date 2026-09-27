#!/usr/bin/env bash
# Runs as root on the task host, piped in over SSH by ../harden-ssh.
# Idempotent. Only run this after confirming the `user` login account can
# already SSH in and reach `rbox` via sudo (host:bootstrap) -- this is the
# step that cuts off the root login you're currently using to run it.
set -euo pipefail

conf=/etc/ssh/sshd_config.d/90-rbox-hardening.conf
cat >"$conf" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowUsers user
EOF

sshd -t # validate first -- refuses to leave a broken config live on reload
systemctl reload sshd

echo "OK: sshd hardened. Root login and password auth are now disabled."
echo "Only 'user' can authenticate over SSH at all -- 'rbox' has no key and"
echo "is reached via 'sudo -u rbox' from a 'user' session, never directly."
echo
echo "Verify from a NEW terminal before closing this session:"
echo "  mise run ssh            # should still work (user, key-only)"
echo "  ssh root@<public-ip>    # should now be refused"
