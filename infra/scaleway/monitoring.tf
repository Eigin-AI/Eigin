# Scaleway Cockpit alerting for the relay. Ingestion is automatic — this file
# adds the alert manager (emails the alerts address), tokens scoped to the
# ruler APIs, and alert rules managed by the community Loki/Mimir providers.
#
# The providers must live in the root module: their config references
# root-level resources (tokens + data source URLs) which a child module
# cannot reference. Rules YAML lives in rules/ separate from the HCL.

locals {
  cockpit_logs_ds = one([
    for s in data.scaleway_cockpit_sources.all.sources : s.url if s.type == "logs"
  ])
  cockpit_metrics_ds = one([
    for s in data.scaleway_cockpit_sources.all.sources : s.url if s.type == "metrics"
  ])
}

# Data source URLs are project + region scoped and stable; look them up
# instead of hardcoding UUIDs per environment. Filtered to the Scaleway-managed
# sources (one logs + one metrics per project).
data "scaleway_cockpit_sources" "all" {
  project_id = scaleway_account_project.eigin.id
  region     = var.scw_region
  origin     = "scaleway"
}

# The alert manager must be in the same region as the data sources.
# No preconfigured alerts — we own the rules.
resource "scaleway_cockpit_alert_manager" "relay" {
  project_id = scaleway_account_project.eigin.id
  region     = var.scw_region

  contact_points {
    email = var.alerts_email
  }
}

# Rules YAML lives in rules/ and is fed via content = file() rather than
# content_file: the loki provider recomputes its state hash from the file
# itself during refresh, which masks in-place edits from every subsequent
# plan/diff. mimir reads live rules instead, but both are fed inline so the
# behavior never depends on provider-version internals: inline content is a
# config attribute, so edits always diff.
#
# Ruler tokens: one per data source, scoped to rule management only. The
# provider needs read access to compare desired vs live rule groups, which
# the full_access rule scope grants. Try to grant nothing broader.
resource "scaleway_cockpit_token" "ruler_logs" {
  project_id = scaleway_account_project.eigin.id
  region     = var.scw_region
  name       = "${var.project_name}-ruler-logs"

  scopes {
    setup_logs_rules = true
  }
}

resource "scaleway_cockpit_token" "ruler_metrics" {
  project_id = scaleway_account_project.eigin.id
  region     = var.scw_region
  name       = "${var.project_name}-ruler-metrics"

  scopes {
    setup_metrics_rules = true
  }
}

# Cockpit scopes auth by Bearer token, not by tenant. It rejects a
# populated X-Scope-OrgID header with 403, so org_id must be empty (both
# providers send the header only when org_id is non-empty). Mimir's ruler
# lives under the /prometheus prefix; Loki's ruler path is relative to the
# data source root.

provider "loki" {
  uri    = local.cockpit_logs_ds
  org_id = ""
  headers = {
    Authorization = "Bearer ${scaleway_cockpit_token.ruler_logs.secret_key}"
  }
}

provider "mimir" {
  ruler_uri = "${local.cockpit_metrics_ds}/prometheus"
  org_id    = ""
  headers = {
    Authorization = "Bearer ${scaleway_cockpit_token.ruler_metrics.secret_key}"
  }
}

resource "loki_rules" "relay" {
  depends_on = [scaleway_cockpit_alert_manager.relay]

  namespace = "eigin-relay"
  content   = file("${path.module}/rules/relay-logs.yaml")
}

resource "mimir_rules" "relay" {
  depends_on = [scaleway_cockpit_alert_manager.relay]

  namespace = "eigin-relay"
  content   = file("${path.module}/rules/relay-metrics.yaml")
}
