# Runbook: manual Hetzner setup before `tofu init`

These are one-time, out-of-band steps on Hetzner's side, plus setting up
SOPS so secrets live encrypted in the repo instead of as plaintext
`export`s in a shell. Do all of this first, then come back to
`tofu init`/`plan`/`apply`.

## 0. Install mise (once, on your machine)

```sh
curl https://mise.run | sh
```

`mise.toml` (repo root) pins `opentofu`, `sops`, `age`, `tflint`,
`gitleaks`, and `pre-commit` — the first `mise run ...` (or `mise install`)
in this repo installs all of them automatically. Every command below is a
`mise run <task>` rather than a raw `sops exec-env '...'` invocation; see
`mise-tasks/` if you want to see exactly what each one runs under the hood.
`age` is the encryption backend SOPS uses here (simpler key management than
PGP/GPG — one keypair, no keyservers, no expiry).

Then, once per clone, wire up the local commit hooks (`tofu fmt`, `tflint`,
`gitleaks`, and the SOPS-encryption check in `.pre-commit-config.yaml`):

```sh
mise exec -- pre-commit install
```

## 1. Generate your age keypair (once, on your machine)

```sh
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

This prints (and saves) a `Public key: age1...` line. The private key stays
in `~/.config/sops/age/keys.txt` — **never commit it, never put it under
`infra/`.** Back it up somewhere durable (password manager); if you lose it,
`secrets.enc.yaml` becomes permanently undecryptable.

Point SOPS at it (add to your shell profile so it's always set):

```sh
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
```

## 2. Wire your public key into `.sops.yaml`

Edit the repo's `.sops.yaml` (root of the repo) and replace the placeholder
with the public key printed in step 1:

```yaml
creation_rules:
  - path_regex: infra/secrets\.enc\.yaml$
    age: age1<your real public key>
```

This is what tells `sops -e` which key(s) can decrypt `infra/secrets.enc.yaml`.
Add more `age:` recipients (comma-separated) later if a second operator
needs to decrypt too.

## 3. Hetzner Cloud API token

1. [Hetzner Cloud Console](https://console.hetzner.cloud/) → your project →
   **Security** → **API Tokens** → **Generate API Token**.
2. Permissions: **Read & Write**. Copy the token — shown once.
3. Don't export it. Paste it into `secrets.yaml` in step 7.

## 4. Generate a dedicated SSH key for this project

Use a key dedicated to this VPS rather than your general-purpose one, so
access to this box can be revoked/rotated independently of anything else:

```sh
ssh-keygen -t ed25519 -C "rbox-task-host" -f ~/.ssh/rbox-task-host_ed25519
```

(Add a passphrase when prompted, or leave it empty if this key will be used
non-interactively later.) This produces `~/.ssh/rbox-task-host_ed25519`
(private) and `~/.ssh/rbox-task-host_ed25519.pub` (public).

## 5. Upload the admin SSH key

1. Console → **Security** → **SSH Keys** → **Add SSH Key**.
2. Paste the public key from step 4 (`~/.ssh/rbox-task-host_ed25519.pub`).
3. Name it to exactly match `var.ssh_key_name` — `main.tf` looks it up by
   name via a `data` source and never manages key material itself.
   - CLI equivalent: `hcloud ssh-key create --name <name> --public-key-from-file ~/.ssh/rbox-task-host_ed25519.pub`

## 6. Cloudflare R2 bucket + API token (for remote tofu state)

State lives on Cloudflare R2 rather than Hetzner Object Storage — Hetzner
bills a flat ~$7/mo minimum per bucket no matter how small it is; R2's free
tier (10GB storage, no monthly minimum) comfortably covers a single state
file. This deliberately puts state on a different provider than the VPS
itself.

1. [Cloudflare dashboard](https://dash.cloudflare.com/) → **R2 Object
   Storage** → **Create bucket**.
   - Location hint: optional. R2 defaults to automatic (global) placement;
     pick an EU hint here only if you want state to stay on the same EU
     footing as the VPS — it's config state, not customer data, so it's a
     minor call either way.
2. Name the bucket, then update `versions.tf`'s `backend "s3" { bucket = ... }`
   — the placeholder `"rbox-tofu-state"` in the repo isn't real.
3. Find your **Account ID**, shown on the right-hand side of the R2 overview
   page, and update `versions.tf`'s `endpoints.s3` URL — replace
   `REPLACE_ME_ACCOUNT_ID` with it (`https://<account-id>.r2.cloudflarestorage.com`).
4. R2 → **Manage API tokens** → **Create API token** → permissions
   **Object Read & Write**, scoped to this bucket. This gives you an
   Access Key ID + Secret Access Key — separate from the `HCLOUD_TOKEN`
   API token from step 3 and from your regular Cloudflare account login.
5. Don't export these either. They go into `secrets.yaml` next.

## 7. Encrypt the secrets

```sh
cd infra
cp secrets.yaml.example secrets.yaml
$EDITOR secrets.yaml     # fill in the real HCLOUD_TOKEN / AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
cd ..
mise run secrets:encrypt
```

Commit `infra/secrets.enc.yaml` — it's ciphertext, safe in the repo. Never
commit `infra/secrets.yaml` (the task removes it after encrypting, but it's
also gitignored as a backstop).

## 8. First apply, then bootstrap the host, then close the firewall

There's no static IP or bastion here, so steady-state SSH access happens
over [Tailscale](https://tailscale.com/) (outbound-only from the box — no
inbound port ever needed once it's joined), not an IP allowlist. And
steady-state SSH logs in as `user`, a non-root, key-only login account
created below — never `root`, and never `rbox` either: `rbox` is a
separate, non-SSH-loginable account that actually holds the `docker` group
membership and runs task workloads, reached only via `sudo -u rbox` from a
`user` session. Splitting login from docker-capable is what makes "least
privilege" real here — see `mise-tasks/host/lib/bootstrap-docker.sh` for
the full reasoning. Getting there takes several passes, all within the one
temporary firewall opening from step (a), so there's only ever one window
where the public IP is reachable at all:

**a. First apply, with a temporary opening.** `bootstrap_ssh_cidrs` defaults
to `[]` (fully closed) — for this one apply only, override it with your
current IP:

```sh
curl -s https://ifconfig.me
```

```sh
mise run tofu:init      # you run this — reserved for the human, not the agent
mise run tofu:bootstrap # curls your current IP, opens SSH to it, applies
```

`tofu:bootstrap` is just `tofu:apply` with `-var="bootstrap_ssh_cidrs=[...]"`
set to whatever `ifconfig.me` reports right now — see `mise-tasks/tofu/bootstrap`.

**b. Install and authenticate Tailscale.** SSH in over the now-briefly-open
port, using the dedicated key from step 4:

```sh
ssh -i ~/.ssh/rbox-task-host_ed25519 root@<server_ipv4>   # server_ipv4 is a tofu output
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up                                              # follow the printed browser login link
tailscale ip -4                                           # note this — it's your stable address for the box
```

Add it to the encrypted secrets — `mise run ssh` decrypts `RBOX_TAILSCALE_IP`
from there, the same way `tofu:apply` decrypts `HCLOUD_TOKEN`:

```sh
sops infra/secrets.enc.yaml   # opens $EDITOR on the decrypted contents; add:
                              #   RBOX_TAILSCALE_IP: "<tailscale-ip-from-above>"
                              # save and quit — sops re-encrypts on write
```

Stay in the root SSH session from this step — the next two steps still need
it.

**c. Install Docker and create the `user`/`rbox` accounts.** From your
machine (not the SSH session):

```sh
mise run host:bootstrap
```

This connects as `root@$RBOX_TAILSCALE_IP` and, idempotently: installs
Docker Engine + the Compose plugin from Docker's official apt repo, creates
two accounts, and copies root's `authorized_keys` to `user` so it accepts
the same dedicated key from step 4:

- `rbox` — added to the `docker` group, no password, **no SSH key at all**.
  This is what actually runs `docker compose`/task workloads.
- `user` — password login disabled, gets root's `authorized_keys`, and a
  narrow `/etc/sudoers.d` grant: `user ALL=(rbox) NOPASSWD: ALL`. That's
  scoped to *becoming rbox*, not becoming root — a typo'd `sudo <cmd>`
  lands as rbox's uid, not root's. This is what you actually SSH into.

See `mise-tasks/host/lib/bootstrap-docker.sh` for exactly what runs, and
the file for the caveat that `docker` group membership is host-root-
equivalent regardless of which account holds it — this split narrows
operator-mistake blast radius, it isn't a sandbox against someone who
already holds the SSH key.

**d. Verify the split works — before touching sshd.** In a *second*
terminal, leaving the root session from step (b) open in the first:

```sh
mise run ssh                                   # now connects as user@$RBOX_TAILSCALE_IP
docker ps                                      # should FAIL -- user has no docker group membership
sudo -u rbox docker run --rm hello-world       # should succeed -- confirms the rbox account works
```

Don't proceed to (e) until both the failure and the success happen as
expected. If something's wrong, you still have the root session open in
the first terminal to fix it and re-run `mise run host:bootstrap` (it's
idempotent).

**e. Harden sshd: disable root login and password auth.** Only once (d) is
confirmed:

```sh
mise run host:harden-ssh
```

This writes `PermitRootLogin no`, `PasswordAuthentication no`, and
`AllowUsers user` to an sshd drop-in, runs `sshd -t` to validate the config
before reloading, then reloads sshd. Existing connections (your still-open
root session) aren't killed by this — only new ones are affected — so
immediately verify in a *third*, fresh attempt:

```sh
mise run ssh              # should still work — user, key-only
ssh root@<server_ipv4>    # should now be refused
```

Only after that succeeds should you close the root session from step (b).

**f. Close the firewall.** Back on your machine, re-apply with no override
(picks the `bootstrap_ssh_cidrs = []` default back up), which drops the
temporary rule and denies all inbound from the public internet again:

```sh
mise run tofu:apply
```

From here on, plan/apply never need any override — `terraform.tfvars`
supplies everything else automatically:

```sh
mise run tofu:plan
mise run tofu:apply
```

Connect from now on over Tailscale as `user`, never as `root` — and use
`sudo -u rbox <cmd>` for anything docker-related once you're in (e.g.
`sudo -u rbox docker ps`). Whether `task:run` itself runs on this host at
all, and how the repo/`mise`/secrets get there for `rbox` to use, isn't
resolved by this step — see `task/README.md` and PLAN.md for where that
stands:

```sh
mise run ssh
```
