# ------------------------------------------------------------------------------
# VPC NETWORK & SUBNET FOR BAZEL CLUSTER
# ------------------------------------------------------------------------------

resource "google_compute_network" "bazel_vpc" {
  name                    = "bazel-vpc"
  auto_create_subnetworks = false # Best practice: define subnets manually
}

resource "google_compute_subnetwork" "bazel_subnet" {
  name          = "bazel-subnet"
  ip_cidr_range = "10.0.0.0/20" # Supports up to 4,096 IP addresses
  region        = var.region
  network       = google_compute_network.bazel_vpc.id

  # Required for GKE Private Clusters / Workload Identity
  private_ip_google_access = true
}
