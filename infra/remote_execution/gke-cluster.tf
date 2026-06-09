# ------------------------------------------------------------------------------
# GKE CLUSTER DEFINITION
# ------------------------------------------------------------------------------
resource "google_container_cluster" "bazel_cluster" {
  name     = var.cluster_name
  location = var.region

  # Use our custom VPC network and subnet
  network    = google_compute_network.bazel_vpc.id
  subnetwork = google_compute_subnetwork.bazel_subnet.id

  # Satisfy Org Policies: Enable Private Nodes AND Private Endpoint
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "172.16.0.0/28" # Small private range for the GKE master VMs
  }

  # Required when private endpoint is enabled
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.0/20"
      display_name = "bazel-subnet-local"
    }
  }

  # Enable GKFE DNS Endpoint and allow external (corp) traffic to route through it
  control_plane_endpoints_config {
    dns_endpoint_config {
      allow_external_traffic = true
    }
  }

  # We can't create a cluster without at least one node pool, so we create
  # a temporary one and delete it immediately.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {}

  # Enable Workload Identity for secure access to GCS without keys
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

variable "cluster_name" {
  type    = string
  default = "bazel-hybrid-cluster"
}

# ------------------------------------------------------------------------------
# 1. CONTROL PLANE NODE POOL (Always On, Small, Cheap)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "control_plane" {
  name       = "control-plane-pool"
  location   = var.region
  cluster    = google_container_cluster.bazel_cluster.name
  node_count = 1 # Always on to receive requests instantly

  node_config {
    preemptible     = false
    machine_type    = "e2-standard-2" # 2 vCPU, 8GB RAM (sufficient for Redis + Queue)
    service_account = google_service_account.gke_nodes.email

    labels = {
      role = "control-plane"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# ------------------------------------------------------------------------------
# 2. LINUX WORKER NODE POOL (Autoscaled to ZERO)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "linux_workers" {
  name     = "worker-pool-linux"
  location = var.region
  cluster  = google_container_cluster.bazel_cluster.name

  # Scale to zero enabled!
  autoscaling {
    min_node_count = 0
    max_node_count = 20
  }

  # Start with 0 nodes
  initial_node_count = 0

  node_config {
    # Spot VMs (preemptible) are perfect for stateless build workers to save 60-80% cost
    spot            = true
    machine_type    = "c2-standard-8" # Compute-optimized, 8 vCPU, 32GB RAM
    service_account = google_service_account.gke_nodes.email

    labels = {
      role = "worker"
      os   = "linux"
    }

    # Taint workers so only Bazel action pods run here
    taint {
      key    = "bazel-worker"
      value  = "true"
      effect = "NO_SCHEDULE"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# ------------------------------------------------------------------------------
# 3. WINDOWS WORKER NODE POOL (Commented out for PoC simplicity)
# ------------------------------------------------------------------------------
# resource "google_container_node_pool" "windows_workers" {
#   name     = "worker-pool-windows"
#   location = var.region
#   cluster  = google_container_cluster.bazel_cluster.name
# 
#   autoscaling {
#     min_node_count = 0
#     max_node_count = 5
#   }
# 
#   initial_node_count = 0
# 
#   node_config {
#     spot         = true
#     machine_type = "n2-standard-8" # 8 vCPU, 32GB RAM
#     image_type   = "WINDOWS_LTSC_CONTAINER" # Windows Server LTSC
# 
#     labels = {
#       role = "worker"
#       os   = "windows"
#     }
# 
#     taint {
#       key    = "bazel-worker"
#       value  = "true"
#       effect = "NO_SCHEDULE"
#     }
# 
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform"
#     ]
#   }
# }

# ------------------------------------------------------------------------------
# GKE NODE SERVICE ACCOUNT & IAM ROLES (LEAST PRIVILEGE)
# ------------------------------------------------------------------------------
resource "google_service_account" "gke_nodes" {
  account_id   = "bazel-gke-nodes"
  display_name = "GKE Nodes Service Account for Bazel"
}

# Grant minimal roles required for GKE node operations
resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_resource_metadata_writer" {
  project = var.project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}
