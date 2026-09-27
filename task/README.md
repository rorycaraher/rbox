# task

Docker-per-task: runs a single headless coding-agent session in an
ephemeral, network-restricted container and opens a PR if it produced
changes. Either **claude** or **opencode** runs the task, picked per
invocation — never in parallel. Triggered manually, by a human; nothing
here auto-merges or auto-triggers. See [`../CLAUDE.md`](../CLAUDE.md).

## Layout

- `Dockerfile`, `entrypoint.sh` — the task container; branches on `$AGENT`.
- `settings.json` / `opencode-settings.json` — per-agent deny lists (the
  real enforcement, since confirmation prompts are bypassed).
- `proxy/` — Squid forward proxy; only route out. Allowlists by TLS SNI
  (`proxy/allowed_domains.txt`), never decrypting traffic.
- `compose.yml` — `task` has no route to the internet except through
  `proxy`; that network topology is the actual egress boundary.
- `../mise-tasks/task/build`, `run` — human-facing entrypoints. `run`
  writes results to `task/runs/<task-id>/` (gitignored).

## Choosing an agent

```sh
mise run task:run <owner/repo> "<prompt>"                 # AGENT defaults to claude
AGENT=opencode mise run task:run <owner/repo> "<prompt>"
```

`opencode` only supports `ANTHROPIC_API_KEY` here, and ignores `MAX_TURNS`.

## Prerequisites

1. Docker on wherever this runs. One-time on the task host:
   `mise run host:bootstrap` (already done).
2. Agent auth: `ANTHROPIC_API_KEY` or, for `claude`, `CLAUDE_CODE_OAUTH_TOKEN`
   (`claude setup-token`, bills against your subscription instead).
3. `GITHUB_TOKEN` — a PAT used to clone/push/open PRs. Currently one
   long-lived token shared across all repos (known simplification).

Add secrets via `sops infra/secrets.enc.yaml`.

## Running

```sh
mise run task:run <owner/repo> "<prompt>" [base_branch]
```

Check `task/runs/<task-id>/`: `result.json` (full agent output),
`summary.json` (`{status, repo, branch, pr_url, detail}`), `pr_url.txt`.

## Not built yet

OTel export, per-task GitHub credential scoping — see `../PLAN.md`.
