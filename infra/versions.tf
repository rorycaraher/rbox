terraform {
  required_version = ">= 1.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }

  # Cloudflare R2, accessed through the S3-compatible backend. Chosen over
  # Hetzner Object Storage purely on cost: Hetzner bills a flat ~$7/mo
  # minimum per bucket regardless of size, R2's free tier covers a state
  # file this small. State living on a different provider than the compute
  # (Hetzner Cloud) is a deliberate decoupling, not an oversight.
  #
  # The bucket must already exist (create it out-of-band — this backend
  # config can't bootstrap the very bucket it depends on) and credentials
  # come from the standard AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY env
  # vars, using an R2 API token's S3-compatible access key pair.
  backend "s3" {
    bucket = "rbox-tofu-state" # TODO: set to the actual bucket name
    key    = "rbox/infra/terraform.tfstate"
    region = "auto" # R2's own convention; not a real AWS region, validation is skipped below

    endpoints = {
      s3 = "https://62aa79ca5a4eb69594dcd5b96f00b4bd.r2.cloudflarestorage.com" # TODO: your Cloudflare account ID
    }

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true # R2 doesn't support AWS's newer checksum algorithm
    use_path_style              = true
  }
}

provider "hcloud" {
  # token comes from the HCLOUD_TOKEN env var
}
