# Roadmap and open concerns

## Phase 1 — single VPS, Docker-per-task

Infra and the task container are built — see `CLAUDE.md` for the current
architecture. What's *not* done yet: nothing has actually run end-to-end.
The remaining Phase 1 work is a proof of concept — one Claude Code task,
billed against a personal Pro subscription, opening one simple PR on a
throwaway test repo — and it needs a way to run on the VPS itself rather
than a laptop, which nothing built so far provides. Full step-by-step in
[`POC-RUNBOOK.md`](POC-RUNBOOK.md); short version:

- [ ] Create a throwaway GitHub repo dedicated to this PoC.
- [ ] Provision the `rbox` runner account on the VPS with what it needs to
      drive `mise run task:run` there directly (git, mise, and — via
      `mise.toml` — sops/age), plus its own age keypair so it can decrypt
      `infra/secrets.enc.yaml` without ever holding your laptop's key.
- [ ] Add that keypair's public half as a second recipient in `.sops.yaml`,
      re-encrypt with `sops updatekeys`.
- [ ] Add `CLAUDE_CODE_OAUTH_TOKEN` (Pro subscription billing, via `claude
      setup-token`) and a `GITHUB_TOKEN` scoped to just the test repo.
- [ ] From a shell on the VPS (as `rbox`), run `mise run task:run` against
      the test repo with a low `MAX_TURNS` for this first run.
- [ ] Confirm a PR actually opened.

Once this works, Phase 1 is done and the pattern (VPS-resident checkout,
its own secrets access) carries forward into Phase 2 below.

## Phase 2 — CI-triggered runs

Self-hosted GitHub Actions runner (same VPS or a small pool) picks up
PR/issue events and runs headless Claude Code in a fresh container per run
— the owned-infra version of `anthropics/claude-code-action`, with control
over the runner, egress rules, and secret storage. Same rule as Phase 1:
**never auto-merge** — agent runs in isolation, opens a branch/PR, existing
CI (tests, lint) runs against it like any other PR, human approval.

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

## Future ideas (not scheduled)

- **Scale out**: dispatcher + worker fleet — a simple queue or polled task
  table, workers that are just the Docker-per-task pattern replicated
  across boxes or Kubernetes jobs, central tracking of task state/diffs/cost
  per run. git worktrees stay useful as the lightweight,
  same-trust-boundary version of parallelism (already in use locally) —
  good within one trusted repo, not a substitute for container isolation
  across many/untrusted repos. Only worth revisiting if Phase 2 throughput
  actually needs it — not a near-term priority.

Don't "fix" these unprompted — they're tracked, sequenced choices, not
oversights.
