# ------------------------------------------------------------------------------
# GKE CLUSTER DEFINITION
# ------------------------------------------------------------------------------
resource "google_container_cluster" "bazel_cluster" {
  name     = var.cluster_name
  location = var.region

  # We can't create a cluster without at least one node pool, so we create
  # a temporary one and delete it immediately.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    # Enabled for VPC-native cluster (required for modern GKE features)
    use_ip_aliases = true
  }

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
    preemptible  = false
    machine_type = "e2-standard-2" # 2 vCPU, 8GB RAM (sufficient for Redis + Queue)

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
    spot         = true
    machine_type = "c2-standard-8" # Compute-optimized, 8 vCPU, 32GB RAM

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
# 3. WINDOWS WORKER NODE POOL (Autoscaled to ZERO)
# ------------------------------------------------------------------------------
resource "google_container_node_pool" "windows_workers" {
  name     = "worker-pool-windows"
  location = var.region
  cluster  = google_container_cluster.bazel_cluster.name

  autoscaling {
    min_node_count = 0
    max_node_count = 5
  }

  initial_node_count = 0

  node_config {
    spot         = true
    machine_type = "n2-standard-8" # 8 vCPU, 32GB RAM
    image_type   = "WINDOWS_LTSC_CONTAINER" # Windows Server LTSC

    labels = {
      role = "worker"
      os   = "windows"
    }

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
