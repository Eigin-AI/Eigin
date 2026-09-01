terraform {
  required_version = ">= 1.10"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.49"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Manage Cockpit alert rules (Loki for logs, Mimir for metrics) as
    # Terraform resources. Self-signed community providers; the lock file
    # pins the checksums. The 1.0/1.1 majors are verified against Cockpit;
    # loki 2.x currently fails to install from the registry.
    loki = {
      source  = "fgouteroux/loki"
      version = "~> 1.0"
    }
    mimir = {
      source  = "fgouteroux/mimir"
      version = "~> 1.1"
    }
  }

  # State defaults to local (terraform.tfstate.d/, gitignored). To use remote
  # state, copy backend.tf.example to backend.tf and follow the runbook:
  # docs/src/runbooks/terraform-remote-state.md
}
