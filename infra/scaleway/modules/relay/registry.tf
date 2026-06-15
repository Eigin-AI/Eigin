resource "scaleway_registry_namespace" "relay" {
  name       = local.namespace
  region     = var.scw_region
  is_public  = false
  project_id = var.scw_project_id
}

resource "docker_image" "relay" {
  name = local.image_ref

  build {
    context    = var.relay_src_dir
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
  }

  keep_locally = false
}

resource "docker_registry_image" "relay" {
  name          = local.image_ref
  keep_remotely = true

  depends_on = [docker_image.relay]
}
