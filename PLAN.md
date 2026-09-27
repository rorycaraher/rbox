# Roadmap and open concerns

Phase 1 (single VPS, Docker-per-task) is built — see `CLAUDE.md` for the
current architecture. This file tracks what's intentionally deferred:
phases not yet built, and cross-cutting concerns not yet resolved.

## Phase 2 — CI-triggered runs

Self-hosted GitHub Actions runner (same VPS or a small pool) picks up
PR/issue events and runs headless Claude Code in a fresh container per run
— the owned-infra version of `anthropics/claude-code-action`, with control
over the runner, egress rules, and secret storage. Same rule as Phase 1:
**never auto-merge** — agent runs in isolation, opens a branch/PR, existing
CI (tests, lint) runs against it like any other PR, human approval.

## Phase 3 — scale out (only if throughput actually needs it)

Dispatcher + worker fleet: a simple queue or polled task table, workers
that are just the Docker-per-task pattern replicated across boxes or
Kubernetes jobs, central tracking of task state/diffs/cost per run. git
worktrees stay useful as the lightweight, same-trust-boundary version of
parallelism (already in use locally) — good within one trusted repo, not a
substitute for container isolation across many/untrusted repos.

## Open cross-cutting concerns

- **Observability**: `claude -p`'s `CLAUDE_CODE_ENABLE_TELEMETRY=1` OTel
  support exists but has nowhere to point to yet (no
  Prometheus/Grafana/Datadog/Honeycomb endpoint). `result.json` per run is
  the only record right now.
- **Cost control**: no per-task budget or turn limit yet; once OTel export
  exists, use its cost metrics (tagged by session) to see which
  repos/task types are actually worth automating.
- **Secrets scope**: `GITHUB_TOKEN` is one long-lived PAT shared across
  every target repo a task runs against, not a per-task/per-repo
  short-lived credential — a GitHub App would fix this at the cost of
  setting one up first.
- **Image drift**: the per-task container image is an infra artifact like
  any other — should be versioned and rebuilt on a schedule eventually, not
  hand-patched.
- **Resumability**: decide whether interrupted/failed tasks retry from
  scratch or resume (`--resume`/`--continue` exist for this) before it
  matters.
- **Inbound allowlisting**: container egress is allowlisted at the network
  layer, but there's no equivalent allowlist restricting inbound-to-VPS
  traffic by SaaS IP range — SaaS IP ranges aren't stable enough to
  allowlist reliably; still open.
- **Hosting location**: keep in mind if scope ever expands beyond your own
  codebases to anything touching customer/personal data — self-hosting in
  the EU avoids extra data-transfer questions a US-hosted managed product
  could raise.

Don't "fix" these unprompted — they're tracked, sequenced choices, not
oversights.
