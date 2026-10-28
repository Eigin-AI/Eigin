terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = ">= 2.73"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

variable "project_name" {
  description = "Dedicated project for public website content."
  type        = string
}

resource "scaleway_account_project" "website" {
  name = var.project_name
  lifecycle {
    prevent_destroy = true
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  bucket_name = "${var.project_name}-${random_id.bucket_suffix.hex}"
}

variable "region" {
  description = "Object Storage region."
  type        = string
  default     = "fr-par"
}

variable "domains" {
  description = "Custom hostnames served by this pipeline with managed TLS."
  type        = list(string)
  default     = []
}

resource "scaleway_object_bucket" "website" {
  project_id = scaleway_account_project.website.id
  region     = var.region
  name       = local.bucket_name
  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_object_bucket_policy" "website" {
  bucket     = scaleway_object_bucket.website.name
  project_id = scaleway_account_project.website.id
  region     = var.region
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicRead"
      Effect    = "Allow"
      Principal = { SCW = "*" }
      Action    = "s3:GetObject"
      Resource  = "${scaleway_object_bucket.website.name}/*"
    }]
  })
}

resource "scaleway_object_bucket_website_configuration" "website" {
  bucket     = scaleway_object_bucket.website.name
  project_id = scaleway_account_project.website.id
  region     = var.region
  index_document {
    suffix = "index.html"
  }
  error_document {
    key = "404.html"
  }
}

resource "scaleway_edge_services_plan" "website" {
  project_id = scaleway_account_project.website.id
  name       = "starter"
}

resource "scaleway_edge_services_pipeline" "website" {
  depends_on  = [scaleway_edge_services_plan.website]
  project_id  = scaleway_account_project.website.id
  name        = local.bucket_name
  description = "Eigin static website"
  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_edge_services_backend_stage" "website" {
  project_id  = scaleway_account_project.website.id
  depends_on  = [scaleway_object_bucket_policy.website, scaleway_object_bucket_website_configuration.website]
  pipeline_id = scaleway_edge_services_pipeline.website.id
  s3_backend_config {
    bucket_name   = scaleway_object_bucket.website.name
    bucket_region = var.region
    is_website    = true
  }
}

resource "scaleway_edge_services_cache_stage" "website" {
  project_id       = scaleway_account_project.website.id
  pipeline_id      = scaleway_edge_services_pipeline.website.id
  backend_stage_id = scaleway_edge_services_backend_stage.website.id
  fallback_ttl     = 300
}

resource "scaleway_edge_services_tls_stage" "website" {
  project_id          = scaleway_account_project.website.id
  count               = length(var.domains) > 0 ? 1 : 0
  pipeline_id         = scaleway_edge_services_pipeline.website.id
  cache_stage_id      = scaleway_edge_services_cache_stage.website.id
  managed_certificate = true
}

resource "scaleway_edge_services_dns_stage" "website" {
  project_id     = scaleway_account_project.website.id
  pipeline_id    = scaleway_edge_services_pipeline.website.id
  tls_stage_id   = length(var.domains) > 0 ? scaleway_edge_services_tls_stage.website[0].id : null
  cache_stage_id = length(var.domains) == 0 ? scaleway_edge_services_cache_stage.website.id : null
  fqdns          = var.domains
}

resource "scaleway_edge_services_head_stage" "website" {
  pipeline_id   = scaleway_edge_services_pipeline.website.id
  head_stage_id = scaleway_edge_services_dns_stage.website.id
}

output "bucket_name" {
  description = "Publishing target."
  value       = scaleway_object_bucket.website.name
}
output "s3_endpoint" {
  description = "S3-compatible publishing endpoint."
  value       = "https://s3.${var.region}.scw.cloud"
}
output "preview_url" {
  description = "Generated HTTPS endpoint used for release verification."
  value       = "https://${scaleway_edge_services_dns_stage.website.default_fqdn}"
  depends_on  = [scaleway_edge_services_head_stage.website]
}
