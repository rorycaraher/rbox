#!/usr/bin/env bash
# Fails if a SOPS-encrypted file's ciphertext body changed in this
# changeset but its SOPS metadata block (the `sops:` key at the bottom --
# mac, lastmodified, per-recipient stanzas) did not. A real edit made via
# `sops` always updates both together, so "data changed, metadata didn't"
# means the file was hand-edited instead, or a git merge stitched together
# two conflicting encrypted versions into something whose MAC no longer
# matches its data. sops itself will refuse to decrypt that, but nothing
# else here (check-sops-encrypted.sh included -- it only checks structure)
# would otherwise catch it at review time.
#
# Compares each given file's current (working-tree) content against its
# content at $SOPS_METADATA_CHECK_BASE (default: HEAD -- i.e. the last
# commit, which is right for a local pre-commit hook running before a
# commit is made). CI sets this explicitly to the PR's base SHA or the
# pre-push SHA. Needs that ref actually present in the local clone -- a
# shallow checkout makes this fail loudly rather than silently skip.
set -euo pipefail

base="${SOPS_METADATA_CHECK_BASE:-HEAD}"

if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "ERROR: can't resolve base ref '${base}' to compare against." >&2
  echo "The checkout needs more git history for this check (fetch-depth: 0, or fetch that SHA)." >&2
  exit 1
fi

metadata_line() {
  grep -n '^sops:' "$1" 2>/dev/null | head -1 | cut -d: -f1
}

status=0
for f in "$@"; do
  [[ -f "$f" ]] || continue

  new_meta_line="$(metadata_line "$f")"
  if [[ -z "$new_meta_line" ]]; then
    echo "ERROR: $f has no top-level 'sops:' metadata block -- not a SOPS-encrypted file?" >&2
    status=1
    continue
  fi

  if ! git cat-file -e "${base}:${f}" 2>/dev/null; then
    continue # new file in this changeset -- nothing to compare a change against
  fi

  old_content="$(git show "${base}:${f}")"
  old_meta_line="$(printf '%s\n' "$old_content" | grep -n '^sops:' | head -1 | cut -d: -f1)"
  if [[ -z "$old_meta_line" ]]; then
    continue # wasn't a SOPS file at $base -- nothing meaningful to compare
  fi

  old_data="$(printf '%s\n' "$old_content" | head -n "$((old_meta_line - 1))")"
  old_meta="$(printf '%s\n' "$old_content" | tail -n "+${old_meta_line}")"
  new_data="$(head -n "$((new_meta_line - 1))" "$f")"
  new_meta="$(tail -n "+${new_meta_line}" "$f")"

  if [[ "$old_data" != "$new_data" && "$old_meta" == "$new_meta" ]]; then
    echo "ERROR: $f's encrypted content changed vs ${base}, but its SOPS metadata" >&2
    echo "(mac/lastmodified) did not. A real 'sops' edit always updates both --" >&2
    echo "this usually means the file was hand-edited outside sops, or a merge" >&2
    echo "combined two conflicting encrypted versions. Re-decrypt and re-encrypt" >&2
    echo "it properly (sops $f) and recommit." >&2
    status=1
  fi
done

exit "$status"
