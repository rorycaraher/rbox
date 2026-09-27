# Self-Hosted Agentic Claude Code Infra — Project Plan

## Goal

Move from running Claude Code interactively, one repo at a time, on a local
machine, to running it headlessly on owned infrastructure (starting with a
single VPS) across multiple repos in the org — with the option to scale to a
fleet later. Infra is self-hosted by choice, not a managed remote-agent
product.

## Core building block

- Claude Code's **headless mode**: `claude -p "<prompt>"` — non-interactive,
  no TUI, no permission prompts, single structured response to stdout
  (`--output-format json` for machine parsing), exit code reflects
  success/failure. This is what everything below is built around.
- The **Agent SDK** is available if programmatic control (rather than
  shelling out to the CLI) turns out to be worth it later.

## Phase 1 — single VPS, Docker-per-task

- One VPS running Docker.
- Each task/session gets its **own ephemeral container**: clone the target
  repo in, run `claude -p` with `--dangerously-skip-permissions`, capture the
  diff, open a branch/PR, tear the container down.
- Rationale for per-task isolation rather than one long-lived shared box: in
  an interactive local session a human catches bad ideas early (wrong repo,
  wrong directory, a sketchy install); in headless automation those
  checkpoints disappear, so the sandbox boundary has to absorb that risk
  instead.
- `--dangerously-skip-permissions` is a **sandbox-only** pattern — never used
  against a workflow that still points at a dev laptop, shared bastion, or
  production-like runner, since that removes the human approval step without
  replacing it with infra-level control.
- Restrict container network egress to only what's needed (Anthropic API,
  GitHub, package registry) — this is also what lets headless runs proceed
  without manual network-access prompts.
- Add an explicit tool/command allowlist in `settings.json` rather than
  relying on the skip-permissions flag as the only control.

### Provisioning

- VPS: Hetzner **CX22** (2 vCPU / 4GB RAM / 40GB disk), region **`fsn1`**
  (Falkenstein) — same EU footing as the "hosting location" concern below.
- Provisioned via **OpenTofu**, code lives in this repo under `infra/`:
  - `hcloud_server` (CX22, `fsn1`).
  - `hcloud_firewall` — denies all inbound from the public internet by
    default. SSH access is over **Tailscale** (outbound-only from the box,
    no inbound port needed once joined) rather than an IP allowlist —
    there's no static admin IP or bastion to allowlist against. A
    `bootstrap_ssh_cidrs` variable (default `[]`, closed) temporarily opens
    tcp/22 to a one-time IP only to install Tailscale on a fresh box, then
    reverts. This does **not** solve the egress restriction called out
    above (Anthropic API/GitHub/package registry only) — SaaS IP ranges
    aren't stable enough to allowlist reliably; that stays a separate,
    still-open problem.
  - SSH key referenced via a `data "hcloud_ssh_key"` lookup by name — the
    key is added to Hetzner out-of-band; tofu never touches key material.
  - State is **remote**: Cloudflare R2 via the S3-compatible backend, not
    local — a single laptop holding the only copy of state is a durability
    risk, not a simplification worth keeping. R2 over Hetzner Object
    Storage on cost alone (Hetzner bills a flat ~$7/mo minimum per bucket
    regardless of size); state living on a different provider than the
    compute is a deliberate trade, not an oversight.
- `tofu plan`/`apply` are run manually, by a human — never by CI or an
  agent. Same principle as "Never auto-merge" below, applied to infra.

## Phase 2 — CI-triggered runs

- Self-hosted GitHub Actions runner (on the same VPS or a small pool) picks up
  PR/issue events and runs headless Claude Code in a fresh container per run
  — the owned-infra version of `anthropics/claude-code-action`, with control
  over the runner, egress rules, and secret storage.
- **Never auto-merge.** Agent runs in isolation → opens a branch/PR → existing
  CI (tests, lint) runs against it like any other PR → human approval.

## Phase 3 — scale out (only if throughput actually needs it)

- Dispatcher + worker fleet: a simple queue or polled task table, workers
  that are just the Docker-per-task pattern replicated across boxes or
  Kubernetes jobs, central tracking of task state / diffs / cost per run.
- git worktrees stay useful as the lightweight, same-trust-boundary version
  of parallelism (already in use locally) — good within one trusted repo,
  not a substitute for container isolation across many/untrusted repos.

## Cross-cutting concerns (build in from Phase 1, not bolted on later)

- **Observability**: Claude Code has native OpenTelemetry support
  (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) exporting cost-in-USD, token counts by
  type (including cache reads), session counts, and lines-of-code changed,
  plus per-call log events — to Prometheus/Grafana, Datadog, Honeycomb, etc.
  Headless runs have no console output otherwise, so this is the only way to
  debug a failure nobody was watching.
- **Cost control**: per-task budgets or turn limits; use OTel cost metrics
  (tagged by session) to see which repos/task types are actually worth
  automating.
- **Secrets scope**: per-task/per-repo credential scope, short-lived tokens
  injected at container start — not one broad deploy key shared across all
  tasks on a box.
- **Image drift**: the per-task container image is an infra artifact like any
  other — versioned and rebuilt on a schedule, not hand-patched.
- **Resumability**: decide whether interrupted/failed tasks retry from scratch
  or resume (`--resume` / `--continue` exist for this) before it matters.
- **Hosting location**: keep in mind if scope ever expands beyond your own
  codebases to anything touching customer/personal data — self-hosting in the
  EU avoids extra data-transfer questions a US-hosted managed product could
  raise.

## Suggested first milestone

A single VPS, one Dockerfile for the task container, manual trigger,
network egress locked to Anthropic + GitHub + package registry, OTel wired to
whatever the team already uses for metrics. Everything past that (queueing,
CI triggers, multi-node) only gets built once this milestone shows which
repos/tasks are actually worth automating.
