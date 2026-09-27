# PoC runbook: one headless PR, running on the VPS

This is the step-by-step for the very first end-to-end run of this repo:
one Claude Code task, billed against a personal Pro subscription, running
on the task host (not a laptop), opening one small PR on a throwaway test
repo. If you've never touched `rbox` before, start here — `CLAUDE.md`
explains the architecture, `task/README.md` is the terse day-to-day
reference once this has worked at least once.

Everything below is run by a human, by hand, watching the output at each
step. Nothing here self-triggers.

## What "done" looks like

A pull request exists on a test repo you created, opened by a bot-flavored
GitHub identity, containing one small, sane diff, with `task/runs/<id>/`
on the VPS holding a `summary.json` with `"status": "pr_opened"` and a
matching `pr_url.txt`. That's it — the PR doesn't need to be mergeable or
even correct; the point is proving the pipe works end to end.

## Prerequisites

- `mise run host:bootstrap` already run on the VPS (Docker + the
  `user`/`rbox` accounts exist). If you're not sure, `mise run ssh` should
  work, and `sudo -u rbox docker run --rm hello-world` should succeed from
  inside that session.
- Your laptop can already decrypt `infra/secrets.enc.yaml` (i.e. `sops
  infra/secrets.enc.yaml` opens cleanly).

## Step 0 — create the test repo

Create a new, empty, throwaway GitHub repo under your own account — public
or private, your call. Don't point this first run at a real project.

Note its `owner/repo` — you'll need it in step 5.

## Step 1 — give `rbox` its own tooling and a checkout

From your laptop:

```sh
mise run host:bootstrap-runner
```

This installs git and mise on the VPS, clones `rbox` into
`/home/rbox/rbox`, runs `mise install` there (which pulls in sops/age per
this repo's own `mise.toml`), and generates an age keypair belonging to
`rbox` if one doesn't already exist. It prints that key's public half at
the end — copy it, you need it next.

## Step 2 — let the VPS decrypt secrets on its own

Open `.sops.yaml`. The `age:` line currently has one recipient (your
laptop). Add the VPS key from step 1 as a second, comma-separated
recipient:

```yaml
creation_rules:
  - path_regex: infra/secrets\.yaml$
    age: <your-existing-laptop-key>,<the-new-vps-key-from-step-1>
```

Then, from your laptop, re-encrypt so both keys can decrypt the existing
file:

```sh
sops updatekeys infra/secrets.enc.yaml
```

Confirm the added recipient when prompted. Commit both changes
(`.sops.yaml` and `infra/secrets.enc.yaml`) — this is a normal,
non-destructive git change, and CI's
`scripts/check-sops-encrypted.sh`/`gitleaks` checks will tell you
immediately if anything went wrong.

## Step 3 — add the two credentials this run needs

Both go in via `sops infra/secrets.enc.yaml` (opens `$EDITOR` on decrypted
content, re-encrypts on save — never hand-edit the ciphertext).

**`CLAUDE_CODE_OAUTH_TOKEN`** — bills this run against your personal Pro
subscription instead of pay-per-token API usage. Generate it once, on your
laptop (needs a browser):

```sh
claude setup-token
```

Paste the resulting token into the sops-opened editor as
`CLAUDE_CODE_OAUTH_TOKEN: <token>`.

**`GITHUB_TOKEN`** — a GitHub fine-grained personal access token, scoped to
*only* the test repo from step 0, with **Contents** and **Pull requests**
set to read/write and nothing else. Create it at
github.com/settings/personal-access-tokens, then add it the same way:
`GITHUB_TOKEN: <token>`.

## Step 4 — get onto the VPS as `rbox`

```sh
mise run ssh
sudo -u rbox -i
cd ~/rbox
git pull --ff-only   # picks up the .sops.yaml / secrets.enc.yaml changes from steps 2-3
```

## Step 5 — run it

Still as `rbox`, on the VPS:

```sh
MAX_TURNS=10 mise run task:run <owner>/<test-repo> "Add a one-line note to README.md saying this repo is used to test headless agent runs."
```

`MAX_TURNS=10` is deliberate for this first run only — there's no
per-task budget/turn-limit control built yet (see `PLAN.md`), and a low
cap bounds how far a confused agent can run against your subscription
before you notice. Don't carry it forward as a default for real tasks.

Keep the prompt this narrow on purpose — something with essentially one
reasonable diff, so a glance at the PR is enough to tell if it worked.

## Step 6 — check the result

The command prints either a PR URL or a `summary.json` dump on exit. To
double check, on the VPS:

```sh
cat ~/rbox/task/runs/<task-id>/summary.json
cat ~/rbox/task/runs/<task-id>/pr_url.txt
```

Then open the PR URL in a browser and read the diff.

## If something goes wrong

- **`set ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN`** — step 3's
  `CLAUDE_CODE_OAUTH_TOKEN` didn't make it into the container's env. Check
  it's actually present in `infra/secrets.enc.yaml` (`sops -d
  infra/secrets.enc.yaml`, on the VPS as `rbox`) and that you `git pull`ed
  after adding it.
- **`agent_failed` in `summary.json`, nonzero exit** — read
  `result.json` in the same run directory; it's the full `claude -p`
  JSON output including whatever error it hit.
- **`no_changes` in `summary.json`** — the agent ran but the working tree
  was clean afterward. Usually means the prompt was too vague or the agent
  decided nothing needed changing; check `result.json` for its reasoning.
- **Agent output mentions a blocked/unreachable domain** — something it
  tried to reach isn't in `task/proxy/allowed_domains.txt`. Add the domain
  there if it's legitimately needed (e.g. a package registry), rebuild
  (`mise run task:build`), and re-run.
- **`gh: command not found` / PR creation fails with an auth error** — the
  `GITHUB_TOKEN` from step 3 is missing, expired, or doesn't have
  `contents`/`pull-requests` write on that specific repo.
- **`sops updatekeys` or `sops -d` fails on the VPS** — `rbox`'s age key
  either wasn't generated (re-run `host:bootstrap-runner`) or isn't the
  one listed in `.sops.yaml` yet (recheck step 2, and that you committed
  and pulled it).

## After a successful run

Phase 1 in `PLAN.md` is done. Update its checklist there, and see Phase 2
for what's next (CI-triggered runs instead of a manually-invoked one-off).
