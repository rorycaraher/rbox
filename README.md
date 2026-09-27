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
