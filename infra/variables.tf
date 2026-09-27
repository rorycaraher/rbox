variable "bootstrap_ssh_cidrs" {
  description = "Temporary public SSH allowlist, used only to install Tailscale on a fresh box. Defaults closed — set to your current IP for the bootstrap apply, then revert to [] and re-apply. See RUNBOOK.md step 8."
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Name of an SSH key already uploaded to Hetzner Cloud (console or API). Tofu only looks it up, never manages key material."
  type        = string
}

variable "server_name" {
  description = "Name of the Hetzner Cloud server."
  type        = string
  default     = "rbox-task-host"
}

variable "image" {
  description = "Base OS image for the server. Docker install and other configuration happen outside tofu."
  type        = string
  default     = "ubuntu-24.04"
}
