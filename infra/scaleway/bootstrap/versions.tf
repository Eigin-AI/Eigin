terraform {
  required_version = ">= 1.10"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.49"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # This root keeps local state on purpose: it creates the bucket the main root's
  # remote state lives in. Its state is small, rarely changed, and operator-held.
}
