locals {
  name       = "${var.project_name}-relay"
  namespace  = var.project_name
  image_name = "rg.${var.scw_region}.scw.cloud/${local.namespace}/${local.name}"
  image_tag = substr(sha1(join("-", [
    sha1(join("", [for f in fileset(var.relay_src_dir, "src/**") : filesha1("${var.relay_src_dir}/${f}")])),
    # config/grant holds environment-specific keys that are not baked into the image.
    sha1(join("", [for f in fileset(var.relay_src_dir, "config/**") : filesha1("${var.relay_src_dir}/${f}") if !startswith(f, "config/grant/")])),
    sha1(join("", [for f in fileset(var.relay_src_dir, "vendor/**") : filesha1("${var.relay_src_dir}/${f}")])),
    filesha1("${var.relay_src_dir}/Cargo.lock"),
    filesha1("${var.relay_src_dir}/Dockerfile"),
    filesha1("${var.relay_src_dir}/Cargo.toml"),
    filesha1("${var.relay_src_dir}/api.yaml"),
  ])), 0, 16)
  image_ref = "${local.image_name}:${local.image_tag}"

  # Relay database connection string. Reused by the container secret and the output the
  # rotate-key tool consumes during a token-key rotation.
  # sslmode=verify-full enforces TLS and validates the server certificate (chain + hostname);
  # without it sqlx defaults to sslmode=prefer, which skips certificate validation.
  # The endpoint already ships "?sslmode=require", so strip its query before setting ours.
  # https://www.scaleway.com/en/docs/serverless-sql-databases/api-cli/secure-connection-ssl-tls/
  db_endpoint  = split("?", trimprefix(scaleway_sdb_sql_database.db.endpoint, "postgres://"))[0]
  database_url = "postgresql://${scaleway_iam_application.db.id}:${scaleway_iam_api_key.db.secret_key}@${local.db_endpoint}?sslmode=verify-full"
}
