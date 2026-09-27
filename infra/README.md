# infra

OpenTofu for the Phase 1 task host: one Hetzner CX22 VPS (`fsn1`) plus a
firewall that denies all inbound from the public internet. SSH access is
over [Tailscale](https://tailscale.com/), not an IP allowlist — there's no
static admin IP or bastion to allowlist against. See [`../PLAN.md`](../PLAN.md)
for the rationale.

`tofu plan`/`apply` are run manually, by a human — never by CI or an agent.

## Prerequisites (one-time, out-of-band)

1. An SSH key uploaded to Hetzner Cloud, matching `var.ssh_key_name`.
2. A Cloudflare R2 bucket for remote state, matching the `bucket` value and
   account ID in `versions.tf`'s endpoint URL. R2 over Hetzner Object
   Storage purely on cost — no flat monthly minimum.
3. Secrets (`HCLOUD_TOKEN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
   live SOPS-encrypted at `infra/secrets.enc.yaml`, committed to the repo —
   never as plaintext `export`s. See [`RUNBOOK.md`](./RUNBOOK.md).
4. Tailscale installed and joined on the box itself — a one-time bootstrap
   over a briefly-opened firewall rule. See `RUNBOOK.md` step 8.

Full step-by-step: [`RUNBOOK.md`](./RUNBOOK.md).

## Variables

`ssh_key_name` has no default and is set in `terraform.tfvars` (gitignored,
machine-local). `bootstrap_ssh_cidrs` defaults to `[]` (fully closed) — it's
only ever set temporarily, for the one-time Tailscale bootstrap. See
`RUNBOOK.md` step 8.

## Running tofu

Run these from the repo root via `mise` — they wrap `sops exec-env` so
secrets are decrypted into the child process's environment only, never
typed or persisted as plaintext, and never as a raw command you have to
remember. `terraform.tfvars` is picked up automatically, no `-var` flags
needed for everyday use:

```sh
mise run tofu:init
mise run tofu:plan
mise run tofu:apply
```

(`mise run tofu:bootstrap` and `mise run secrets:encrypt` cover the two
one-time setup steps in `RUNBOOK.md`. See `mise-tasks/` for what each task
actually runs.)
