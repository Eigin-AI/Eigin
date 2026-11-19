terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.73"
    }
  }
}

variable "project_name" {
  description = "Dedicated project for the contributor portal."
  type        = string
}

variable "region" {
  description = "Region for the container and database."
  type        = string
}

resource "scaleway_account_project" "portal" {
  name = var.project_name
  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_registry_namespace" "portal" {
  project_id = scaleway_account_project.portal.id
  region     = var.region
  name       = var.project_name
  is_public  = false
}

resource "scaleway_container_namespace" "portal" {
  project_id = scaleway_account_project.portal.id
  region     = var.region
  name       = var.project_name
}
