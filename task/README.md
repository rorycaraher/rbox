# task

Docker-per-task: the actual thing that runs a single headless Claude Code
session in an ephemeral, network-restricted container and opens a PR if it
produced changes. See [`../PLAN.md`](../PLAN.md) Phase 1 for the rationale.
This is triggered manually, by a human, same as `tofu apply` — nothing here
auto-merges or auto-triggers itself.

## Layout

- `Dockerfile`, `entrypoint.sh`, `settings.json` — the task container. Clones
  the target repo over HTTPS with a short-lived token, runs
  `claude -p --dangerously-skip-permissions`, and if the working tree changed,
  pushes a branch and opens a PR via `gh`. Runs as a non-root user.
  `settings.json` is loaded from `CLAUDE_CONFIG_DIR` (outside the cloned
  repo) and carries a `permissions.deny` list — `deny` is what's actually
  doing anything here, since `allow` prompts are already skipped by
  `--dangerously-skip-permissions`.
- `proxy/` — a Squid forward proxy the task container is forced through
  (`HTTP_PROXY`/`HTTPS_PROXY`, and no other route out — see `compose.yml`'s
  network shape). Allowlists domains by TLS SNI via `ssl_bump peek`+`splice`,
  never decrypting traffic. The allowed list is
  `proxy/allowed_domains.txt` — Anthropic, GitHub, and the common package
  registries by default; edit it for what a given repo's build actually
  needs.
- `compose.yml` — wires `task` and `proxy` together. `task` sits on an
  `internal: true` network with no route to the internet at all; `proxy` is
  dual-homed onto that network and a normal one. That's the actual egress
  boundary — the allowlist is enforced by network topology, not just Squid
  config, so a task that ignores the proxy env vars still can't reach
  anything.
- `../mise-tasks/task/build`, `../mise-tasks/task/run` — human-facing
  entrypoints. `run` decrypts `GITHUB_TOKEN` plus whichever of
  `ANTHROPIC_API_KEY`/`CLAUDE_CODE_OAUTH_TOKEN` is set from
  `../infra/secrets.enc.yaml` into the child process only (same `sops
  exec-env` pattern as `tofu:apply`), brings the pair up for one task, tears
  both down (`down -v`) when it exits, and writes result JSON / the PR URL
  to `task/runs/<task-id>/` (gitignored).

## Prerequisites

1. Docker installed on wherever this runs (the task host, or your own
   machine for local testing/iteration — see below). Not provisioned by
   tofu — `infra/variables.tf` says as much (`image` is a bare Ubuntu image).
   On the task host, this is one-time, from your own machine (not over
   `mise run ssh` — see `infra/RUNBOOK.md` step 8):

   ```sh
   mise run host:bootstrap
   ```

   This installs Docker and creates two accounts on the host: `user` (who
   you SSH in as) and `rbox` (in the `docker` group, reached only via
   `sudo -u rbox` from a `user` session — never SSH'd into directly). Any
   `docker`/`docker compose` command below, run on the host itself rather
   than your own machine, needs that `sudo -u rbox` prefix.

2. `claude -p` auth: set **one** of `ANTHROPIC_API_KEY` or
   `CLAUDE_CODE_OAUTH_TOKEN` (`entrypoint.sh` requires at least one, and
   `claude` itself picks whichever is present).
   - `ANTHROPIC_API_KEY` — pay-per-token, from console.anthropic.com.
   - `CLAUDE_CODE_OAUTH_TOKEN` — bills against a Claude **Pro/Max/Team/
     Enterprise subscription** instead of API credits. Generate it on a
     machine with a browser (your laptop, not the headless task host —
     there's no browser there to complete the OAuth flow):

     ```sh
     claude setup-token
     ```

     This prints a token, valid for about a year. Two things worth knowing
     before relying on it for unattended runs: it authenticates as *your*
     account, so every task container shares your normal Pro/Max rate
     limit/weekly usage cap rather than getting its own budget — a task can
     stall mid-run if you hit that cap doing other things the same week;
     and when it does expire, headless runs will just start failing with an
     auth error until you re-run `claude setup-token` and update the secret
     below. There's no email/warning ahead of expiry.

   Add whichever one you're using the same way `RBOX_TAILSCALE_IP` was
   added: `sops infra/secrets.enc.yaml`, edit, save.

3. `GITHUB_TOKEN` alongside it, same way — a PAT (classic `repo` scope, or
   fine-grained scoped to the specific repos you'll point tasks at) used to
   clone, push, and open PRs. This is a known simplification for the first
   milestone: it's a long-lived token shared across whatever repos you run
   tasks against, not the per-task/per-repo short-lived credential
   PLAN.md's "Secrets scope" section calls for eventually — a GitHub App
   installation token would get you that, at the cost of setting up a
   GitHub App first.

## Running a task

```sh
mise run task:run <owner/repo> "<prompt>"                # base branch: repo default
mise run task:run <owner/repo> "<prompt>" <base_branch>  # explicit base branch
```

Each run builds fresh images (no stale task state carried between runs),
runs the container, and tears the whole compose project down on exit
whether it succeeded or not. Check `task/runs/<task-id>/`:

- `result.json` — full `claude -p --output-format json` output (cost,
  turns, the works — see PLAN.md's Observability section; this is the
  closest thing to a log a headless run has right now, short of wiring real
  OTel export).
- `summary.json` — `{status, repo, branch, pr_url, detail}`.
- `pr_url.txt` — just the URL, if one was opened.

## What's deliberately not here yet

- **OTel export.** `claude -p` supports `CLAUDE_CODE_ENABLE_TELEMETRY=1` and
  the usual `OTEL_EXPORTER_*` vars — not wired up because there's no
  Prometheus/Grafana/Datadog/Honeycomb endpoint to point it at yet. Add the
  env vars to `compose.yml`'s `task` service once there is one.
- **Per-task GitHub credential scoping.** See the `GITHUB_TOKEN` note above.
- **Local testing note:** `mise run task:run` works from a laptop too
  (nothing here is task-host-specific), which is the easy way to iterate on
  the Dockerfile/proxy allowlist before it matters that this eventually runs
  unattended on the VPS.
