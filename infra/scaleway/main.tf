resource "scaleway_account_project" "eigin" {
  name = var.project_name
}

module "relay" {
  source = "./modules/relay"

  relay_src_dir      = "${path.root}/${var.relay_src_dir}"
  project_name       = var.project_name
  scw_secret_key     = var.scw_secret_key
  scw_project_id     = scaleway_account_project.eigin.id
  scw_region         = var.scw_region
  mojeek_api_key     = var.mojeek_api_key
  eigin_relay_key    = var.eigin_relay_key
  monthly_pool_size  = var.monthly_pool_size
  max_scale          = var.max_scale
}
