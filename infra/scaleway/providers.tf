provider "scaleway" {
  # All credentials and region are read from the Scaleway CLI config.
  # Run `scw init` to configure the CLI before running terraform.
}

# The registry endpoint is deterministic from variables alone, so we can
# configure auth here without creating a dependency on the module output.
provider "docker" {
  registry_auth {
    address  = "rg.${var.scw_region}.scw.cloud"
    username = "any" # Scaleway ignores the username; secret key is the password
    password = var.scw_secret_key
  }
}
