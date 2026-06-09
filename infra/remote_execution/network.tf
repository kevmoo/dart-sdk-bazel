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

# ------------------------------------------------------------------------------
# CLOUD NAT (Allows private GKE nodes to talk outbound to the internet)
# ------------------------------------------------------------------------------

resource "google_compute_router" "router" {
  name    = "bazel-router"
  region  = var.region
  network = google_compute_network.bazel_vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "bazel-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
