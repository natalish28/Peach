terraform {
  required_version = ">= 1.10"

  # A second workspace with its own state: a plan here cannot touch AWS, and an AWS plan cannot
  # touch Google Cloud. Runs get short-lived Google credentials through Workload Identity
  # Federation (TFC_GCP_* variables on the workspace, created by gcp/bootstrap).
  cloud {
    organization = "miunafw"

    workspaces {
      name = "peach-gcp"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = {
    project    = var.project_name
    managed-by = "terraform"
  }
}

# The Firebase resources live in google-beta. Their APIs want a quota project.
provider "google-beta" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}
