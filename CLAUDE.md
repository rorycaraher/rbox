# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infra for running Claude Code **headlessly** on owned infrastructure (a
single Hetzner VPS to start) instead of interactively on a laptop, one
Docker container per task. See `PLAN.md` for the full rationale and phased
roadmap (Phase 1: single VPS, Docker-per-task — what's built now; Phase 2:
CI-triggered runs; Phase 3: scale-out fleet — not built yet).

Two independent pieces live here:

- `infra/` — OpenTofu that provisions the VPS itself.
- `task/` — the Docker-per-task sandbox that actually runs a headless
  `claude -p` session against some *other* target repo.

## Commands

All commands run through `mise run <task>` from the repo root (never invoke
`tofu`/`sops`/`docker compose` directly — the mise-tasks wrap secret
decryption via `sops exec-env` so credentials never touch a shell as
plaintext). Task definitions live in `mise-tasks/` as plain bash scripts —
read one directly to see exactly what it runs.

```sh
mise run tofu:init                                        # human-run only
mise run tofu:plan                                         # human-run only
mise run tofu:apply                                        # human-run only
mise run tofu:bootstrap                                    # one-time: temp-open SSH, apply, see RUNBOOK.md step 8
mise run tofu:fmt
mise run secrets:encrypt                                   # infra/secrets.yaml -> secrets.enc.yaml, removes plaintext
mise run ssh                                                # SSH to the task host over Tailscale
mise run task:build                                         # build task+proxy images, no secrets, no run
mise run task:run <owner/repo> "<prompt>" [base_branch]     # run one headless task
```

Linting/validation (also what CI runs, via `pre-commit run --all-files`):
`tofu fmt`, `tofu validate` (with `-backend=false`, no cloud creds needed),
`tflint`, `gitleaks`, and `scripts/check-sops-encrypted.sh` (verifies
`infra/secrets.enc.yaml` is actually ciphertext). One `.pre-commit-config.yaml`
drives both local hooks and CI — no separate check list to keep in sync.

There is no test suite; this is infra config, not application code.

## Hard boundaries — do not cross these

- **Never run `tofu apply`/`plan`/`init`/`destroy`/`import` or mutating
  `state` subcommands.** Same for `mise run tofu:*` beyond `fmt`. These are
  run manually, by a human, always — this is also enforced by the user's own
  global instructions, not just this repo's convention. Stop at the code/config
  change and say it's ready for the human to apply.
- **Never auto-merge, and never run `mise run task:run`, `git push`, or
  `gh pr` commands yourself.** Task runs and their resulting PRs are
  triggered manually by a human; nothing in this repo self-triggers.
- **Never commit `infra/secrets.yaml`** (plaintext staging file, gitignored)
  — only `infra/secrets.enc.yaml` (SOPS ciphertext) is meant to be committed.
  If asked to add a secret, edit via `sops infra/secrets.enc.yaml` (opens
  `$EDITOR` on decrypted content, re-encrypts on save), not by hand-editing
  the ciphertext file or writing a new plaintext one.

## Architecture

### `infra/` — the VPS itself

- Single `hcloud_server` (Hetzner CX22, `fsn1`) plus an `hcloud_firewall`
  that denies all inbound by default (`main.tf`). Steady-state SSH is over
  Tailscale (outbound-only from the box); `bootstrap_ssh_cidrs` is a
  temporary, normally-empty variable used only once to install Tailscale
  over a briefly-opened port (`RUNBOOK.md` step 8) — this does **not**
  restrict container egress, that's a separate mechanism (see `task/` below).
- SSH key is looked up by name via `data "hcloud_ssh_key"` — tofu never
  manages key material; the key is uploaded to Hetzner out-of-band.
- State is remote: Cloudflare R2 via the S3-compatible backend
  (`versions.tf`), deliberately on a different provider than the compute.
  `versions.tf` has two placeholders (`bucket`, account-ID in the R2
  endpoint URL) that must be set to the real values before `tofu init` works
  — see `infra/README.md` prerequisites.
- Secrets (`HCLOUD_TOKEN`, R2 access key pair, `RBOX_TAILSCALE_IP`, and the
  task-container secrets below) all live SOPS-encrypted in one file,
  `infra/secrets.enc.yaml`, keyed by an age recipient in `.sops.yaml`. Every
  mise-task that needs them decrypts via `sops exec-env` into the child
  process's environment only.

### `task/` — the Docker-per-task sandbox

One `docker compose -p <task-id> up` per task (`mise-tasks/task/run`),
torn down (`down -v`) on exit regardless of outcome. Two services
(`compose.yml`):

- `task` — clones the target repo (short-lived `x-access-token` over
  HTTPS using `GITHUB_TOKEN`), runs `claude -p --dangerously-skip-permissions
  --output-format json`, and if the working tree changed, commits, pushes a
  `rbox/task-<id>` branch, and opens a PR via `gh` (`entrypoint.sh`). Runs
  as non-root (`agent` user in `Dockerfile`).
- `proxy` — a Squid forward proxy the task container is forced through.
  Allowlists domains by TLS SNI only (`ssl_bump peek`+`splice` — never
  decrypts traffic); the allowlist is `proxy/allowed_domains.txt`.

The actual egress boundary is **network topology**, not just Squid config:
`task` sits on an `internal: true` compose network with no route to the
internet at all and can only reach `proxy`, which is dual-homed onto both
that network and a normal egressing one. A task that ignores the
`HTTP_PROXY`/`HTTPS_PROXY` env vars still has no path out.

Because `--dangerously-skip-permissions` disables Claude Code's own
confirmation prompts, the remaining control is `task/settings.json`'s
`permissions.deny` list (loaded via `CLAUDE_CONFIG_DIR`, outside the cloned
repo, so the target repo's own content can never override it) — e.g. deny
`sudo`/`su`, force-push, `git config --global`, reading SSH/AWS credential
paths. This is the layer actually doing something here, since `allow`
prompts are already bypassed by the skip-permissions flag.

Per-task output (`result.json` = full `claude -p` JSON output including
cost/turns; `summary.json` = `{status, repo, branch, pr_url, detail}`;
`pr_url.txt`) lands in `task/runs/<task-id>/` (gitignored) via a bind mount
set by `RBOX_OUTPUT_HOST_DIR`.

`claude -p` auth is **either** `ANTHROPIC_API_KEY` (pay-per-token) **or**
`CLAUDE_CODE_OAUTH_TOKEN` (bills against a Claude subscription instead;
generated once via `claude setup-token` on a machine with a browser, since
the headless host has none). Exactly one should be set in
`infra/secrets.enc.yaml`; `entrypoint.sh` requires at least one.

## Known, deliberate simplifications (not bugs)

- `GITHUB_TOKEN` is one long-lived PAT shared across every target repo a
  task runs against, not a per-task/per-repo short-lived credential — a
  GitHub App would fix this at the cost of setting one up first.
- No OTel/observability export wired up yet (`claude -p`'s
  `CLAUDE_CODE_ENABLE_TELEMETRY=1` support exists but has nowhere to point
  to). `result.json` per run is the only record right now.
- Container egress is allowlisted at the network layer, but there's no
  equivalent allowlist restricting inbound-to-VPS traffic by SaaS IP range
  (noted as a still-open problem in `PLAN.md`).

Don't "fix" these unprompted — they're tracked, sequenced choices, not
oversights. `PLAN.md` is the source of truth for what's intentionally
deferred to a later phase.
