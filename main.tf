terraform {
  required_version = ">= 1.5"
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 6.3"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 6.9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.9"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

data "google_storage_project_service_account" "default" {
  project = var.project_id
}

locals {
  base_apis = [
    "artifactregistry.googleapis.com",
    "cloudkms.googleapis.com",
    "containerscanning.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage-api.googleapis.com",
    "sts.googleapis.com",
  ]
  # APIs required for Infrastructure Manager
  infra_manager_apis = [
    "config.googleapis.com",
  ]
  # APIs required for Cloud Deploy
  cloud_deploy_apis = [
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
  ]
}

# Bootstrapping should enable the minimal set of services required to complete bootstrap and permit additional actions to be executed.
resource "google_project_service" "apis" {
  for_each = { for api in setunion(
    local.base_apis,
    var.gcp_options.enable_infra_manager ? local.infra_manager_apis : [],
    var.gcp_options.enable_cloud_deploy ? local.cloud_deploy_apis : [],
    var.bootstrap_apis,
  ) : api => true }
  project                    = var.project_id
  service                    = each.key
  disable_on_destroy         = var.gcp_options.services_disable_on_destroy
  disable_dependent_services = var.gcp_options.disable_dependent_services
}

# This creates the IaC service account that may be used by automation services such as Terraform Cloud, Atlantis or Infra Manager.
resource "google_service_account" "iac" {
  project      = var.project_id
  account_id   = format("%s-iac", var.name)
  display_name = "IaC automation service account"
  description  = <<-EOD
  Service account that may be used by various automation providers to provision Google Cloud resources.
  EOD

  depends_on = [
    google_project_service.apis,
  ]
}

# Bind service account to impersonators
resource "google_service_account_iam_member" "iac_impersonation" {
  for_each = { for i, pair in setproduct(var.iac_impersonators, ["roles/iam.serviceAccountTokenCreator", "roles/iam.serviceAccountUser"]) : tostring(i) => {
    member = pair[0]
    role   = pair[1]
  } }
  service_account_id = google_service_account.iac.name
  member             = each.value.member
  role               = each.value.role

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Bind the IaC automation service account to the necessary project roles.
resource "google_project_iam_member" "iac" {
  for_each = var.iac_roles
  project  = var.project_id
  role     = each.key
  member   = google_service_account.iac.member

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Ensure that required service identities are known if Cloud Deploy is to be enabled.
resource "google_project_service_identity" "ids" {
  for_each = var.gcp_options.enable_cloud_deploy ? { for api in local.cloud_deploy_apis : api => true } : {}
  provider = google-beta
  project  = var.project_id
  service  = each.key

  depends_on = [
    google_project_service.apis,
  ]
}

# This creates the Cloud Deploy execution service account, which can also be used as the Cloud Deploy automation service
# account.
resource "google_service_account" "deploy" {
  for_each     = var.gcp_options.enable_cloud_deploy ? { deploy = format("%s-deploy", var.name) } : {}
  project      = var.project_id
  account_id   = each.value
  display_name = "Cloud Deploy execution service account"
  description  = <<-EOD
  Cloud Deploy execution service account that will be used for pipelines associated with this repo.
  EOD

  depends_on = [
    google_project_service.apis,
  ]
}

# Bind the Cloud Deploy execution service account to job runner role at the project level, which includes access to
# buckets in the project.
resource "google_project_iam_member" "deploy" {
  for_each = google_service_account.deploy
  project  = var.project_id
  role     = "roles/clouddeploy.jobRunner"
  member   = each.value.member

  depends_on = [
    google_project_service.apis,
    google_service_account.deploy,
  ]
}

# Bootstrap the workload identity pool that is associated with this deployment
# repo. This allows short lived OIDC tokens to be authenticated and used for
# invoking APIs directly.
resource "google_iam_workload_identity_pool" "bots" {
  project                   = var.project_id
  workload_identity_pool_id = format("%s-bots", var.name)
  display_name              = format("Automation pool for %s", var.name)
  description               = <<-EOD
  Defines a pool of third-party providers that can exchange tokens for automation actions.
  EOD
  disabled                  = false

  depends_on = [
    google_project_service.apis,
  ]
}

# Bind the workload identity user role on automation service account for principals that satisfy the condition that their respective provider has the custom
# 'iac_sa' attribute set to true.
resource "google_service_account_iam_member" "iac" {
  service_account_id = google_service_account.iac.name
  member             = format("principalSet://iam.googleapis.com/%s/attribute.iac_sa/enabled", google_iam_workload_identity_pool.bots.name)
  role               = "roles/iam.workloadIdentityUser"

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC identities with the custom attribute infra_manager = 'enabled' to manage Infrastructure Manager configs.
resource "google_project_iam_member" "infra_manager" {
  for_each = var.gcp_options.enable_infra_manager ? { member = format("principalSet://iam.googleapis.com/%s/attribute.infra_manager/enabled", google_iam_workload_identity_pool.bots.name) } : {}
  project  = var.project_id
  member   = each.value
  role     = "roles/config.admin"

  depends_on = [
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC identities with the custom attribute infra_manager = 'enabled' to act as IaC service account.
resource "google_service_account_iam_member" "iac_infra_manager" {
  for_each           = var.gcp_options.enable_infra_manager ? { member = format("principalSet://iam.googleapis.com/%s/attribute.infra_manager/enabled", google_iam_workload_identity_pool.bots.name) } : {}
  service_account_id = google_service_account.iac.name
  member             = each.value
  role               = "roles/iam.serviceAccountUser"

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
    google_iam_workload_identity_pool.bots,
  ]
}

# Bind the workload identity user role on Cloud Deploy execution service account for principals that satisfy the
# condition that their respective provider has the custom 'deploy_sa' attribute set to true.
resource "google_service_account_iam_member" "deploy" {
  for_each           = google_service_account.deploy
  service_account_id = each.value.name
  member             = format("principalSet://iam.googleapis.com/%s/attribute.deploy_sa/enabled", google_iam_workload_identity_pool.bots.name)
  role               = "roles/iam.workloadIdentityUser"

  depends_on = [
    google_project_service.apis,
    google_service_account.deploy,
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC identities with the custom attribute cloud_deploy = 'enabled' to release deployments.
resource "google_project_iam_member" "cloud_deploy" {
  for_each = var.gcp_options.enable_cloud_deploy ? { member = format("principalSet://iam.googleapis.com/%s/attribute.deploy_sa/enabled", google_iam_workload_identity_pool.bots.name) } : {}
  project  = var.project_id
  member   = each.value
  role     = "roles/clouddeploy.releaser"

  depends_on = [
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC identities with the custom attribute cloud_deploy = 'enabled' to act as Cloud Deploy execution service account.
resource "google_service_account_iam_member" "deploy_cloud_deploy" {
  for_each           = google_service_account.deploy
  service_account_id = each.value.name
  member             = format("principalSet://iam.googleapis.com/%s/attribute.cloud_deploy/enabled", google_iam_workload_identity_pool.bots.name)
  role               = "roles/iam.serviceAccountUser"

  depends_on = [
    google_project_service.apis,
    google_service_account.deploy,
    google_iam_workload_identity_pool.bots,
  ]
}

# Create a KMS key ring for use by automation modules
resource "google_kms_key_ring" "automation" {
  project  = var.project_id
  name     = format("%s-automation", var.name)
  location = try(lower(var.gcp_options.bucket.location), "global")
  depends_on = [
    google_project_service.apis,
  ]
}

# Allow the IaC automation SA to use any KMS key in the key ring for encryption and decryption
resource "google_kms_key_ring_iam_member" "iac" {
  key_ring_id = google_kms_key_ring.automation.id
  role        = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member      = google_service_account.iac.member

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Create a KMS key solely for external encryption and decryption such as sops operations
resource "google_kms_crypto_key" "sops" {
  name     = format("%s-sops", var.name)
  key_ring = google_kms_key_ring.automation.id
  labels   = var.labels

  depends_on = [
    google_project_service.apis,
  ]
}

# Create a KMS key solely for encrypting bucket objects
resource "google_kms_crypto_key" "gcs" {
  name     = format("%s-gcs", var.name)
  key_ring = google_kms_key_ring.automation.id
  purpose  = "ENCRYPT_DECRYPT"
  labels   = var.labels

  depends_on = [
    google_project_service.apis,
  ]
}

# Allow the default project storage SA to use the state KMS key for encryption and decryption of objects
resource "google_kms_crypto_key_iam_member" "gcs" {
  crypto_key_id = google_kms_crypto_key.gcs.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = data.google_storage_project_service_account.default.member
  depends_on = [
    google_project_service.apis,
  ]
}

# Create a bucket for automation state; defaults are sane for Terraform but can
# be overridden as needed.
resource "google_storage_bucket" "state" {
  project                     = var.project_id
  name                        = format("%s-automation", var.name)
  force_destroy               = try(var.gcp_options.bucket.force_destroy, true)
  labels                      = var.labels
  location                    = try(var.gcp_options.bucket.location, "US")
  storage_class               = try(var.gcp_options.bucket.class, "STANDARD")
  uniform_bucket_level_access = try(var.gcp_options.bucket.uniform_access, true)
  public_access_prevention    = "enforced"
  versioning {
    enabled = try(var.gcp_options.bucket.versioning, false)
  }
  encryption {
    default_kms_key_name = google_kms_crypto_key.gcs.id
  }

  depends_on = [
    google_project_service.apis,
    google_kms_crypto_key_iam_member.gcs,
  ]
}

# Make the IaC automation service account an admin of the bootstrapped bucket.
resource "google_storage_bucket_iam_member" "admin" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.admin"
  member = google_service_account.iac.member

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Ensure the Cloud Deploy execution service account can view and create objects in the bootstrapped bucket.
resource "google_storage_bucket_iam_member" "deploy" {
  for_each = { for i, pair in setproduct([for sa in google_service_account.deploy : sa.member], ["roles/storage.objectViewer", "roles/storage.objectCreator"]) : tostring(i) => {
    member = pair[0]
    role   = pair[1]
  } }
  bucket = google_storage_bucket.state.name
  role   = each.value.role
  member = each.value.member

  depends_on = [
    google_project_service.apis,
    google_service_account.deploy,
  ]
}
