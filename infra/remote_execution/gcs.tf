terraform {
  required_version = ">= 1.0.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0"
    }
  }
}

variable "project_id" {
  type        = string
  description = "The Google Cloud Project ID (Defined in local.auto.tfvars)"
  default     = "<GCP_PROJECT_ID>"
}

variable "region" {
  type        = string
  description = "The GCP region for the buckets"
  default     = "us-central1"
}

variable "bucket_prefix" {
  type        = string
  description = "Prefix to ensure bucket uniqueness"
  default     = "bazel-global-cache"
}

variable "developer_member" {
  type        = string
  description = "The IAM member representing developers (e.g., group:developers@yourdomain.com or user:email@google.com)"
  default     = "group:developers@yourdomain.com"
}

variable "ci_service_account" {
  type        = string
  description = "The CI service account email (optional)"
  default     = ""
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ------------------------------------------------------------------------------
# 1. DEVELOPER CACHE BUCKET (Short TTL, Read-Write for Devs)
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "dev_cache" {
  name          = "${var.bucket_prefix}-dev-${var.project_id}"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  force_destroy               = true # Allow easy cleanup during PoC

  # Scale-to-zero / Cost control: Delete objects older than 14 days
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 14
    }
  }
}

# ------------------------------------------------------------------------------
# 2. PRODUCTION / TOOLCHAIN CACHE BUCKET (Long TTL, Read-Only for Devs)
# ------------------------------------------------------------------------------
resource "google_storage_bucket" "prod_cache" {
  name          = "${var.bucket_prefix}-prod-${var.project_id}"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  force_destroy               = false # Protect production history

  # Long retention to preserve stable toolchains and CI builds
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 180
    }
  }
}

# ------------------------------------------------------------------------------
# 3. IAM PERMISSIONS (TEMPLATE)
# ------------------------------------------------------------------------------

# Developer Member (e.g., group:developers@yourdomain.com or user:email@google.com)
# - Read-Write on Dev Cache
# - Read-Only on Prod Cache
resource "google_storage_bucket_iam_member" "dev_cache_developer_writer" {
  bucket = google_storage_bucket.dev_cache.name
  role   = "roles/storage.objectAdmin" # Allows read, write, and delete (for cache eviction)
  member = var.developer_member
}

resource "google_storage_bucket_iam_member" "prod_cache_developer_reader" {
  bucket = google_storage_bucket.prod_cache.name
  role   = "roles/storage.objectViewer" # Read-only
  member = var.developer_member
}

# CI/CD Service Account (optional, skipped if empty)
# - Read-Write on both buckets
resource "google_storage_bucket_iam_member" "dev_cache_ci_admin" {
  count  = var.ci_service_account != "" ? 1 : 0
  bucket = google_storage_bucket.dev_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.ci_service_account}"
}

resource "google_storage_bucket_iam_member" "prod_cache_ci_admin" {
  count  = var.ci_service_account != "" ? 1 : 0
  bucket = google_storage_bucket.prod_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.ci_service_account}"
}
