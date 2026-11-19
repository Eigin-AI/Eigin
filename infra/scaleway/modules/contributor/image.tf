locals {
  context = "${path.root}/.contributor-image/current"
  files   = sort(tolist(fileset(local.context, "**")))
  tag     = sha256(jsonencode([for f in local.files : [f, filesha256("${local.context}/${f}")]]))
  repo    = "${scaleway_registry_namespace.portal.endpoint}/portal"
  image   = "${local.repo}@${docker_registry_image.portal.sha256_digest}"
}

resource "docker_image" "portal" {
  name = "${local.repo}:${local.tag}"
  build {
    context  = abspath(local.context)
    platform = "linux/amd64"
  }
  lifecycle {
    precondition {
      condition     = contains(local.files, "src/eigin_contributors/build/index.js")
      error_message = "Prepare the portal image with bash src/eigin_contributors/scripts/prepare-image.sh before planning production."
    }
  }
}

resource "docker_registry_image" "portal" {
  name          = docker_image.portal.name
  keep_remotely = true
}
