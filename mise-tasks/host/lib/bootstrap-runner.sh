#!/usr/bin/env bash
# Runs as root on the task host, piped in over SSH by ../bootstrap-runner.
# Idempotent. Assumes host:bootstrap already ran -- the `rbox` docker-runner
# account must already exist.
#
# Gives `rbox` what it needs to drive `mise run task:run` on the VPS
# itself: git, mise (installed the same way bootstrap-docker.sh installs
# Docker -- an apt repo pinned to the vendor's own signing key, not a
# curl-piped-to-shell installer), rbox's own checkout of this repo, and an
# age keypair of its own so it can decrypt infra/secrets.enc.yaml without
# ever touching your laptop's private key. sops/age binaries themselves
# come from `mise install` reading this repo's own mise.toml -- one place
# pins their versions, not two.
set -euo pipefail

RUNNER_USER="rbox"
REPO_URL="https://github.com/rorycaraher/rbox.git"
REPO_DIR="/home/${RUNNER_USER}/rbox"

id -u "$RUNNER_USER" >/dev/null 2>&1 || {
  echo "rbox account missing -- run host:bootstrap first" >&2
  exit 1
}

apt-get update
apt-get install -y git

if ! command -v mise >/dev/null 2>&1; then
  install -dm 755 /etc/apt/keyrings
  wget -qO - https://mise.jdx.dev/gpg-key.pub | gpg --dearmor -o /etc/apt/keyrings/mise-archive-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=$(dpkg --print-architecture)] https://mise.jdx.dev/deb stable main" \
    >/etc/apt/sources.list.d/mise.list
  apt-get update
  apt-get install -y mise
fi

sudo -u "$RUNNER_USER" -H bash -euo pipefail <<EOF
if [[ ! -d "$REPO_DIR/.git" ]]; then
  git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"
git pull --ff-only
mise trust
mise install

age_key_dir="\$HOME/.config/sops/age"
age_key_file="\$age_key_dir/keys.txt"
if [[ ! -f "\$age_key_file" ]]; then
  install -dm 700 "\$age_key_dir"
  mise exec -- age-keygen -o "\$age_key_file"
  chmod 600 "\$age_key_file"
fi

echo
echo "rbox's age public key -- add this as a second, comma-separated"
echo "recipient in .sops.yaml, then from your laptop run:"
echo "  sops updatekeys infra/secrets.enc.yaml"
grep "public key:" "\$age_key_file"
EOF

echo
echo "OK: mise and rbox's checkout at $REPO_DIR are set up."
echo "Next: add the age key above to .sops.yaml, run 'sops updatekeys', then"
echo "add CLAUDE_CODE_OAUTH_TOKEN + GITHUB_TOKEN via 'sops infra/secrets.enc.yaml'."
