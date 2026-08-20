locals {
  name       = "${var.project_name}-relay"
  namespace  = var.project_name
  image_name = "rg.${var.scw_region}.scw.cloud/${local.namespace}/${local.name}"
  image_tag = substr(sha1(join("-", [
    sha1(join("", [for f in fileset(var.relay_src_dir, "src/**") : filesha1("${var.relay_src_dir}/${f}")])),
    # config/grant holds environment-specific keys that are not baked into the image.
    sha1(join("", [for f in fileset(var.relay_src_dir, "config/**") : filesha1("${var.relay_src_dir}/${f}") if !startswith(f, "config/grant/")])),
    filesha1("${var.relay_src_dir}/Dockerfile"),
    filesha1("${var.relay_src_dir}/Cargo.toml"),
    filesha1("${var.relay_src_dir}/api.yaml"),
  ])), 0, 16)
  image_ref = "${local.image_name}:${local.image_tag}"

  # Relay database connection string. Reused by the container secret and the output the
  # rotate-key tool consumes during a token-key rotation.
  database_url = "postgresql://${scaleway_iam_application.db.id}:${scaleway_iam_api_key.db.secret_key}@${trimprefix(scaleway_sdb_sql_database.db.endpoint, "postgres://")}"
}
