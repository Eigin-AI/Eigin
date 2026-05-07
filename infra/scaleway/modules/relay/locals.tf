locals {
  name        = "${var.project_name}-relay"
  namespace   = var.project_name
  image_name  = "rg.${var.scw_region}.scw.cloud/${local.namespace}/${local.name}"
  image_tag = substr(sha1(join("-", [
    sha1(join("", [for f in fileset(var.relay_src_dir, "src/**") : filesha1("${var.relay_src_dir}/${f}")])),
    filesha1("${var.relay_src_dir}/Dockerfile"),
    filesha1("${var.relay_src_dir}/Cargo.toml"),
  ])), 0, 16)
  image_ref   = "${local.image_name}:${local.image_tag}"
  s3_endpoint = "https://s3.${var.scw_region}.scw.cloud"
}
