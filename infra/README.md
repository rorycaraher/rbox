# infra

OpenTofu for the Phase 1 task host: one Hetzner CX22 VPS (`fsn1`) plus a
firewall denying all inbound. SSH is over Tailscale, not an IP allowlist.
See [`../CLAUDE.md`](../CLAUDE.md).

`tofu plan`/`apply` are run manually, by a human — never CI or an agent.

## Prerequisites (one-time, out-of-band)

1. SSH key uploaded to Hetzner, matching `var.ssh_key_name`.
2. Cloudflare R2 bucket for remote state, matching `versions.tf`.
3. Secrets (`HCLOUD_TOKEN`, R2 keys) SOPS-encrypted at `secrets.enc.yaml`,
   via `sops infra/secrets.enc.yaml`.
4. Tailscale joined on the box (one-time bootstrap, already done).

`ssh_key_name` is set in `terraform.tfvars` (gitignored, machine-local).
`bootstrap_ssh_cidrs` defaults to `[]`, only ever set temporarily for the
Tailscale bootstrap.

## Running

```sh
mise run tofu:init
mise run tofu:plan
mise run tofu:apply
```

Run from repo root via `mise` — wraps `sops exec-env` so secrets never
touch a shell as plaintext.
