#!/usr/bin/env bash
# Fails if any given file isn't actually SOPS-encrypted content — a
# backstop against ever committing infra/secrets.enc.yaml (or any future
# file matching .sops.yaml's creation_rules) as plaintext by accident.
#
# `sops filestatus` inspects the file's structure only; it never needs
# decryption capability, so this runs fine in CI without the age private key.
set -euo pipefail

status=0
for f in "$@"; do
  if [[ ! -f "$f" ]]; then
    continue
  fi
  if ! sops filestatus "$f" 2>/dev/null | grep -qE '"encrypted":[[:space:]]*true'; then
    echo "ERROR: $f does not look like a SOPS-encrypted file." >&2
    status=1
  fi
done
exit "$status"
