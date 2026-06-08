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

# Developer Group (e.g., developers@yourdomain.com)
# - Read-Write on Dev Cache
# - Read-Only on Prod Cache
resource "google_storage_bucket_iam_member" "dev_cache_developer_writer" {
  bucket = google_storage_bucket.dev_cache.name
  role   = "roles/storage.objectAdmin" # Allows read, write, and delete (for cache eviction)
  member = "group:developers@yourdomain.com" # PLACEHOLDER
}

resource "google_storage_bucket_iam_member" "prod_cache_developer_reader" {
  bucket = google_storage_bucket.prod_cache.name
  role   = "roles/storage.objectViewer" # Read-only
  member = "group:developers@yourdomain.com" # PLACEHOLDER
}

# CI/CD Service Account (e.g., github-actions@project.iam.gserviceaccount.com)
# - Read-Write on both buckets
resource "google_storage_bucket_iam_member" "dev_cache_ci_admin" {
  bucket = google_storage_bucket.dev_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:ci-builder@${var.project_id}.iam.gserviceaccount.com" # PLACEHOLDER
}

resource "google_storage_bucket_iam_member" "prod_cache_ci_admin" {
  bucket = google_storage_bucket.prod_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:ci-builder@${var.project_id}.iam.gserviceaccount.com" # PLACEHOLDER
}
