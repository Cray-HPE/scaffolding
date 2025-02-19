/**
 * Copyright 2022 The Sigstore Authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// GKE cluster setup.

// Enable required services for this module
resource "google_project_service" "service" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com", // For IAM bindings. roles/resourcemanager.projectIamAdmin
    "compute.googleapis.com",              // For Node Pool, roles/compute.instanceAdmin
    "container.googleapis.com",            // For GKE cluster. roles/container.admin
    "iam.googleapis.com",                  // For creating service accounts and access control. roles/iam.serviceAccountAdmin, roles/iam.serviceAccountUser
  ])
  project = var.project_id
  service = each.key

  // Do not disable the service on destroy. On destroy, we are going to
  // destroy the project, but we need the APIs available to destroy the
  // underlying resources.
  disable_on_destroy = false
}

resource "google_container_cluster" "cluster" {
  # This is where to enable Dataplane v2.
  datapath_provider = var.datapath_provider

  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  release_channel {
    channel = var.channel
  }

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  node_config {
    metadata = {
      disable-legacy-endpoints = true
    }
    service_account = google_service_account.gke-sa.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  resource_labels = {
    "env" = var.cluster_name
  }

  timeouts {
    create = var.timeouts_create
    update = var.timeouts_update
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  networking_mode = var.networking_mode
  network         = var.network
  subnetwork      = var.subnetwork

  // Use VPC Aliasing to improve performance and reduce network hops between nodes and load balancers.  References the secondary ranges specified in the VPC subnet.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.cluster_secondary_range_name
    services_secondary_range_name = var.services_secondary_range_name
  }

  // Specify the list of CIDRs which can access the master's API
  master_authorized_networks_config {
    cidr_blocks {
      display_name = var.display_name
      cidr_block   = format("%s/32", var.bastion_ip_address)
    }
  }

  // Configure the cluster to have private nodes and private control plane access only
  private_cluster_config {
    enable_private_endpoint = var.enable_private_endpoint
    enable_private_nodes    = var.enable_private_nodes
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
  }

  # GKE Dataplane v2 comes with network policy, network policy needs to be disabled to enable dataplane v2.
  network_policy {
    enabled  = var.network_policy_enabled
    provider = var.network_policy_provider
  }

  cluster_autoscaling {
    autoscaling_profile = var.cluster_autoscaling_profile
    enabled             = var.cluster_autoscaling_enabled

    resource_limits {
      resource_type = "cpu"
      minimum       = var.resource_limits_resource_cpu_min
      maximum       = var.resource_limits_resource_cpu_max
    }

    resource_limits {
      resource_type = "memory"
      minimum       = var.resource_limits_resource_mem_min
      maximum       = var.resource_limits_resource_mem_max
    }
  }

  depends_on = [google_project_service.service]
}
