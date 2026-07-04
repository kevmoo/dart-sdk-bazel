# Bazel Remote Execution & Caching Infrastructure

# 🚨 CRITICAL SAFETY RULE: DO NOT PUSH TO GITHUB 🚨

> [!CAUTION]
> **DO NOT PUSH THIS BRANCH (`remote-execution-infra`) TO THE PUBLIC GITHUB REPOSITORY (`origin`).**
> 
> This branch contains infrastructure templates that, if misconfigured or populated with real values during local testing, could leak sensitive Google Cloud credentials, Project IDs, or network topology.
> 
> **Before any push is ever considered:**
> 1. Run a comprehensive automated and manual scrub of all files.
> 2. Verify that `local.auto.tfvars` and other private files are not tracked (check `git status`).
> 3. Obtain explicit sign-off from the lead researcher (kevmoo@).

---

This directory contains the infrastructure-as-code (Terraform) and Kubernetes configurations for deploying a hybrid, distributed Bazel remote execution and caching system.

## Architecture Overview

The system is designed to route build and test actions dynamically:
*   **Control Plane / Queue**: Hosted on Google Kubernetes Engine (GKE) in a permanent, low-cost node pool.
*   **Linux Workers**: Hosted on GKE, scaling from `0` to `N` using **KEDA** based on queue depth.
*   **Windows Workers**: Hosted on GKE (Windows Server nodes), scaling from `0` to `M`.
*   **macOS Workers**: Hosted externally (e.g., AWS EC2 Mac or on-premise), running a pull-based worker daemon connecting outbound to the GKE queue.
*   **Storage**: A split GCS bucket strategy to maximize cache hits while preventing infinite storage growth.

---

## Security Protocol (No Leaks!)

> [!IMPORTANT]
> **NEVER commit real Google Cloud Project IDs, service account keys, IP addresses, or domain names to this repository.**

All configuration files in this directory use placeholders:
*   `<GCP_PROJECT_ID>`
*   `<GCP_REGION>`
*   `<GKE_CLUSTER_NAME>`
*   `<DEV_CACHE_BUCKET_NAME>`
*   `<PROD_CACHE_BUCKET_NAME>`

### How to Deploy Locally (Securely)

1.  Create a file named `local.auto.tfvars` in this directory. This file is explicitly added to `.gitignore` and will **never** be committed.
2.  Populate it with your real Google Cloud details:
    ```hcl
    project_id   = "your-actual-gcp-project-id"
    region       = "us-west1"
    cluster_name = "your-gke-cluster"
    ```
3.  Use Application Default Credentials (ADC) for authentication:
    ```bash
    gcloud auth application-default login
    ```

---

## Directory Structure

*   `gcs.tf`: Terraform configuration for the split-bucket GCS cache.
*   `gke-cluster.tf`: Terraform template for the heterogeneous GKE cluster (Linux + Windows pools).
*   `buildfarm-values.yaml`: Helm values template for deploying Buildfarm.
*   `bazelrc`: Template `.bazelrc` configuration for developers.

---

## Verification Status

### Phase 1: GCS Remote Caching (VERIFIED & ACTIVE)
*   **Status**: Completed on 2026-06-08
*   **Target Project**: `<GCP_PROJECT_ID>`
*   **Provisioned Buckets**:
    *   Dev Cache: `<DEV_CACHE_BUCKET_NAME>` (14-day TTL)
    *   Prod Cache: `<PROD_CACHE_BUCKET_NAME>` (180-day TTL)
*   **Results**:
    *   **Cold Build (Cache Miss)**: `40.251s` (5 processes: 1 internal, 4 linux-sandbox) - Populated GCS.
    *   **Warm Build (Cache Hit)**: `8.248s` (5 processes: 1 internal, **4 remote cache hit**) - 100% hit rate.

#### How to Re-Verify Locally
Run the following command to force a clean build and pull everything from the GCS cache:
```bash
bazel clean --expunge && \
bazel build //samples/embedder:futures_kernel_dill_compile \
  --remote_cache=https://storage.googleapis.com/<DEV_CACHE_BUCKET_NAME> \
  --google_default_credentials=true \
  --remote_upload_local_results=true
```

---

## Phase 2: Full Remote Execution (Buildfarm on GKE)

### 1. Prerequisites & Authentication
Before running remote builds, you must configure `kubectl` to communicate with the private GKE cluster.

```bash
gcloud container clusters get-credentials <GKE_CLUSTER_NAME> \
  --region <GCP_REGION> \
  --project <GCP_PROJECT_ID>
```

*(Note: For the sandbox environment, the active values are: cluster `bazel-hybrid-cluster`, region `us-west1`, project `dart-sdk-bazel-sandbox-265004`)*.

### 2. Establish Port-Forwarding Tunnels
Because the Buildfarm and Buildbuddy services inside GKE are deployed as private `ClusterIP` services, you must establish local port-forwarding tunnels. Keep these running in separate terminal windows during your build session:

*   **Buildfarm Server (Remote Executor)** (Port 8980):
    ```bash
    kubectl port-forward -n bazel-buildfarm service/bazel-buildfarm-server 8980:8980 --insecure-skip-tls-verify
    ```
*   **Buildbuddy (BES & Dashboard)** (Ports 1985 & 8080):
    ```bash
    kubectl port-forward -n bazel-buildfarm service/buildbuddy 1985:1985 8080:8080 --insecure-skip-tls-verify
    ```

### 3. Executing Remote Builds
Once the tunnels are active, you can run builds that execute entirely on the remote GKE worker nodes.

#### Option A: Run with Remote Execution & Buildbuddy Dashboard (Recommended)
This command runs the build remotely and outputs a clickable `http://localhost:8080/invocation/...` link to monitor the build in real-time:
```bash
bazel build \
  --config=remote \
  --config=buildbuddy \
  --remote_executor=grpc://localhost:8980 \
  --remote_cache=grpc://localhost:8980 \
  //sdk:create_sdk
```

#### Option B: Run with Remote Execution Only (No Dashboard)
```bash
bazel build \
  --config=remote \
  --remote_executor=grpc://localhost:8980 \
  --remote_cache=grpc://localhost:8980 \
  //sdk:create_sdk
```
