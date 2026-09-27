data "hcloud_ssh_key" "admin" {
  name = var.ssh_key_name
}

resource "hcloud_firewall" "main" {
  name = "${var.server_name}-firewall"

  # Steady state: zero inbound rules, everything inbound denied by
  # Hetzner's default-deny. SSH happens over Tailscale (outbound-only from
  # this box, no inbound port needed) — there's no static admin IP or
  # bastion to allowlist against instead.
  #
  # bootstrap_ssh_cidrs exists only to get Tailscale installed on a fresh
  # box: set it to your current IP, apply, install+auth Tailscale over that
  # temporary opening, then set it back to [] and re-apply. See
  # RUNBOOK.md step 8. This does not restrict egress — allowlisting
  # container egress to Anthropic/GitHub/the package registry stays a
  # separate, still-open problem (see PLAN.md).
  dynamic "rule" {
    for_each = length(var.bootstrap_ssh_cidrs) > 0 ? [1] : []
    content {
      direction  = "in"
      protocol   = "tcp"
      port       = "22"
      source_ips = var.bootstrap_ssh_cidrs
    }
  }
}

resource "hcloud_server" "task_host" {
  name         = var.server_name
  server_type  = "cpx22"
  location     = "fsn1"
  image        = var.image
  ssh_keys     = [data.hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.main.id]
}
