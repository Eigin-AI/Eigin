terraform {
  required_version = ">= 1.7"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.49"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }

  # State defaults to local (terraform.tfstate, gitignored).
  #
  # To migrate to remote state (Scaleway Object Storage), create a file at
  # infra/scaleway/backend.tf (gitignored) with the following content, then
  # run `terraform init -migrate-state`:
  #
  #   terraform {
  #     backend "s3" {
  #       bucket   = "your-tfstate-bucket"
  #       key      = "scaleway/relay/terraform.tfstate"
  #       region   = "fr-par"
  #
  #       endpoints = {
  #         s3 = "https://s3.fr-par.scw.cloud"
  #       }
  #
  #       skip_credentials_validation = true
  #       skip_region_validation      = true
  #       skip_requesting_account_id  = true
  #       use_path_style              = true
  #     }
  #   }
}
