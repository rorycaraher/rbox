# rbox

Runs Claude Code (or opencode) headlessly on owned infra, one Docker
container per task. See [`CLAUDE.md`](./CLAUDE.md) for architecture,
[`PLAN.md`](./PLAN.md) for roadmap.

- [`infra/`](./infra/README.md) — OpenTofu for the VPS.
- [`task/`](./task/README.md) — the Docker-per-task sandbox.

Nothing self-triggers: `tofu apply`/`plan` and `mise run task:run` are
run manually. See [`CLAUDE.md`](./CLAUDE.md) for hard boundaries.

All commands run via `mise run <task>` (never `tofu`/`sops`/`docker
compose` directly — see `mise-tasks/`). No test suite; this is infra
config, not application code.

Run `mise install` once after cloning: it installs the pinned tool
versions (opentofu, sops, tflint, gitleaks, pre-commit, ...) and, via a
`postinstall` hook in `mise.toml`, also installs the local git
pre-commit hook (`pre-commit install`) so the same checks CI runs
(`tofu fmt`/`validate`, `tflint`, `gitleaks`, the SOPS checks) run on
every commit, not just after pushing.

## Tasks

Run `mise tasks` to list these with descriptions straight from the
scripts (each is a plain bash file under `mise-tasks/`, read one
directly for exact behavior).

| Task | What it does |
| --- | --- |
| `mise run tofu:fmt` | `tofu fmt` — no secrets needed |
| `mise run tofu:init` | `tofu init`, secrets decrypted into env via `sops exec-env` — **human-run only** |
| `mise run tofu:plan` | `tofu plan` — **human-run only** |
| `mise run tofu:apply` | `tofu apply` — **human-run only** |
| `mise run tofu:bootstrap` | One-time: temporarily opens SSH to your current IP and applies, so Tailscale can be installed on a fresh box — **human-run only** |
| `mise run host:bootstrap` | One-time: installs Docker and creates the `user`/`rbox` accounts on the task host over SSH — **human-run only** |
| `mise run host:harden-ssh` | One-time: disables root/password SSH login on the task host — **human-run only**, run after confirming `mise run ssh` + `sudo -u rbox` work |
| `mise run ssh` | SSH to the task host over Tailscale as `user` |
| `mise run secrets:encrypt` | Encrypts `infra/secrets.yaml` -> `infra/secrets.enc.yaml`, removes the plaintext |
| `mise run task:build` | Builds the task + proxy Docker images, no secrets, no run |
| `mise run task:run <owner/repo> "<prompt>" [base_branch]` | Runs one headless Docker-per-task Claude Code session against a target repo, opening a PR if it produced changes |

"Human-run only" tasks are never invoked by Claude in this repo — see
`CLAUDE.md`'s "Hard boundaries" for the full list and why.
