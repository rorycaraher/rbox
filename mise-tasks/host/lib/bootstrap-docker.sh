#!/usr/bin/env bash
# Runs as root on the task host, piped in over SSH by ../bootstrap. Idempotent
# -- safe to re-run (e.g. after a failed step, or to pick up a Docker
# version bump).
set -euo pipefail

LOGIN_USER="user"  # SSH login account -- deliberately NOT in the docker group
RUNNER_USER="rbox" # runs docker/task workloads -- deliberately not SSH-loginable

# --- Docker Engine + Compose plugin ---
# Official apt repo, pinned to Docker's own GPG key -- deliberately not the
# get.docker.com convenience script, which curls a script over the box's
# egress and runs it as root with no repo signature to check.
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  arch="$(dpkg --print-architecture)"
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
systemctl enable --now docker

# --- rbox: the docker-group runner account ---
# Runs `mise run task:run`/`docker compose` -- reached via `sudo -u rbox`
# from the login account, never SSH'd into directly. No password, no SSH
# key, and (below) excluded from sshd's AllowUsers -- its only way in is
# `sudo -u rbox` from $LOGIN_USER. Being in the `docker` group is
# host-root-equivalent in practice (unrestricted bind mounts), so this
# account is a deliberate-escalation boundary against operator mistakes,
# not a real sandbox against someone who already holds the SSH key.
if ! id -u "$RUNNER_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$RUNNER_USER"
fi
usermod -aG docker "$RUNNER_USER"
passwd -l "$RUNNER_USER" >/dev/null

# --- user: the SSH login account ---
# Not in the docker group, no password -- authenticates with the same SSH
# key already authorized for root. sshd itself doesn't get locked down to
# key-only/non-root until ../harden-ssh, run as a separate, deliberate step
# once this account is confirmed working (see RUNBOOK.md step 8).
if ! id -u "$LOGIN_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$LOGIN_USER"
fi
passwd -l "$LOGIN_USER" >/dev/null

install -d -m 700 -o "$LOGIN_USER" -g "$LOGIN_USER" "/home/$LOGIN_USER/.ssh"
cp /root/.ssh/authorized_keys "/home/$LOGIN_USER/.ssh/authorized_keys"
chmod 600 "/home/$LOGIN_USER/.ssh/authorized_keys"
chown "$LOGIN_USER:$LOGIN_USER" "/home/$LOGIN_USER/.ssh/authorized_keys"

# sudo, scoped to "run anything, but only as rbox" -- not "as root" and not
# via the broad `sudo` group. NOPASSWD because there's no password to
# prompt for; the SSH private key is the only credential that ever
# authenticates $LOGIN_USER. This means a typo'd `sudo <cmd>` lands as
# rbox's uid, not root's -- real root still requires deliberately going
# through docker, same caveat as above.
sudoers_file="/etc/sudoers.d/90-${LOGIN_USER}"
echo "${LOGIN_USER} ALL=(${RUNNER_USER}) NOPASSWD: ALL" >"$sudoers_file"
chmod 440 "$sudoers_file"
visudo -cf "$sudoers_file"

echo "OK: $(docker --version)"
echo "OK: $(id "$LOGIN_USER")"
echo "OK: $(id "$RUNNER_USER")"
echo
echo "Next: from your machine, confirm BEFORE running host:harden-ssh:"
echo "  mise run ssh                              # connects as ${LOGIN_USER}"
echo "  docker ps                                  # should FAIL -- ${LOGIN_USER} has no docker access"
echo "  sudo -u ${RUNNER_USER} docker run --rm hello-world  # should succeed"
