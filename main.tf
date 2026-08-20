terraform {
  required_version = ">= 1.5"
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 6.12"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 7.31"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.31"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.2"
    }
  }
}

data "google_storage_project_service_account" "default" {
  project = var.project_id
}

locals {
  base_apis = [
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "serviceusage.googleapis.com",
    "sts.googleapis.com",
  ]
  # APIs required for GCS
  storage_apis = [
    "storage-api.googleapis.com",
  ]
  # APIs required for Artifact Registry
  ar_apis = [
    "artifactregistry.googleapis.com",
    "containerscanning.googleapis.com",
  ]
  # APIs required for Infrastructure Manager
  infra_manager_apis = [
    "config.googleapis.com",
    "storage-api.googleapis.com",
  ]
  # APIs required for Cloud Deploy
  cloud_deploy_apis = [
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
  ]
  # APIs required for KMS
  kms_apis = [
    "cloudkms.googleapis.com",
  ]
  # APIs required for Secret Manager
  secret_manager_apis = [
    "secretmanager.googleapis.com",
  ]
  # Will Artifact Registry be required?
  enable_artifact_registry = try(var.gcp_options.ar.oci, true) || try(var.gcp_options.ar.deb, false) || try(var.gcp_options.rpm, false) || local.has_nginx_jwt_secret || local.has_f5_ai_repo_credentials_secret
  # Only create a virtual OCI registry if the flag is set and there is at least one OCI repo.
  enable_virtual_oci_registry = try(var.gcp_options.ar.virtual_oci, false) && (try(var.gcp_options.ar.oci, true) || local.has_nginx_jwt_secret || local.has_f5_ai_repo_credentials_secret)
  # Determine which secrets should be created with corresponding GitHub action values.
  has_nginx_jwt_secret              = try(length(trimspace(var.nginx_jwt)), 0) > 0
  has_f5_ai_license_secret          = try(length(trimspace(var.f5_ai_license)), 0) > 0
  has_f5_ai_repo_credentials_secret = try(length(trimspace(var.f5_ai_repo_credentials.username)), 0) > 0 && try(length(trimspace(var.f5_ai_repo_credentials.password)), 0) > 0
  # List of service identities that are required for the module or for typical demos that use the module
  service_identities = concat(
    try(var.gcp_options.enable_cloud_deploy, true) ? local.cloud_deploy_apis : [],
    local.enable_artifact_registry ? ["artifactregistry.googleapis.com"] : [],
  )
}

# Bootstrapping should enable the minimal set of services required to complete bootstrap and permit additional actions to be executed.
resource "google_project_service" "apis" {
  for_each = { for api in setunion(
    local.base_apis,
    try(var.gcp_options.create_state_bucket, true) ? local.storage_apis : [],
    local.enable_artifact_registry ? local.ar_apis : [],
    try(var.gcp_options.enable_infra_manager, true) ? local.infra_manager_apis : [],
    try(var.gcp_options.enable_cloud_deploy, true) ? local.cloud_deploy_apis : [],
    try(var.gcp_options.kms, false) ? local.kms_apis : [],
    local.has_nginx_jwt_secret || local.has_f5_ai_license_secret || local.has_f5_ai_repo_credentials_secret ? local.secret_manager_apis : [],
    var.bootstrap_apis == null ? [] : var.bootstrap_apis,
  ) : api => true }
  project                    = var.project_id
  service                    = each.key
  disable_on_destroy         = try(var.gcp_options.services_disable_on_destroy, false)
  disable_dependent_services = try(var.gcp_options.disable_dependent_services, false)
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
  for_each = setunion(
    var.iac_roles == null ? [] : var.iac_roles,
    try(var.gcp_options.enable_infra_manager, true) ? ["roles/config.agent"] : [],
  )
  project = var.project_id
  role    = each.key
  member  = google_service_account.iac.member

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Ensure that required service identities are known.
resource "google_project_service_identity" "ids" {
  for_each = { for api in local.service_identities : api => true }
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
  for_each     = try(var.gcp_options.enable_cloud_deploy, true) ? { deploy = format("%s-deploy", var.name) } : {}
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
# buckets in the project, and any other explicit roles provided.
resource "google_project_iam_member" "deploy" {
  for_each = { for i, pair in setproduct([for sa in google_service_account.deploy : sa.member], distinct(compact(concat(["roles/clouddeploy.jobRunner"], try(length(var.cloud_deploy_roles), 0) == 0 ? [] : tolist(var.cloud_deploy_roles))))) : tostring(i) => {
    member = pair[0]
    role   = pair[1]
  } }
  project = var.project_id
  role    = each.value.role
  member  = each.value.member

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
  display_name              = substr(format("Automation pool (%s)", var.name), 0, 32)
  description               = <<-EOD
  Defines a pool of third-party providers that can exchange tokens for automation actions.
  EOD
  disabled                  = false

  depends_on = [
    google_project_service.apis,
  ]
}

# If the flag to enable workload identity pool admin is set for IaC, grant the role on the pool, not project.
resource "google_iam_workload_identity_pool_iam_member" "iac" {
  for_each                  = try(var.iac_options.enable_workload_identity_pool_admin, false) ? { enabled = true } : {}
  project                   = google_iam_workload_identity_pool.bots.project
  workload_identity_pool_id = google_iam_workload_identity_pool.bots.workload_identity_pool_id
  role                      = "roles/iam.workloadIdentityPoolAdmin"
  member                    = google_service_account.iac.member

  depends_on = [
    google_service_account.iac,
    google_iam_workload_identity_pool.bots,
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
  for_each = try(var.gcp_options.enable_infra_manager, true) ? { member = format("principalSet://iam.googleapis.com/%s/attribute.infra_manager/enabled", google_iam_workload_identity_pool.bots.name) } : {}
  project  = var.project_id
  member   = each.value
  role     = "roles/config.admin"

  depends_on = [
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC identities with the custom attribute infra_manager = 'enabled' to act as IaC service account.
resource "google_service_account_iam_member" "iac_infra_manager" {
  for_each           = try(var.gcp_options.enable_infra_manager, true) ? { member = format("principalSet://iam.googleapis.com/%s/attribute.infra_manager/enabled", google_iam_workload_identity_pool.bots.name) } : {}
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

# Allow OIDC identities with the custom attribute deploy_sa = 'enabled' to release deployments.
resource "google_project_iam_member" "cloud_deploy" {
  for_each = try(var.gcp_options.enable_cloud_deploy, true) ? { member = format("principalSet://iam.googleapis.com/%s/attribute.deploy_sa/enabled", google_iam_workload_identity_pool.bots.name) } : {}
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
  for_each = try(var.gcp_options.kms, false) ? { enabled = true } : {}
  project  = var.project_id
  name     = format("%s-automation", var.name)
  location = try(lower(var.gcp_options.bucket.location), "global")
  depends_on = [
    google_project_service.apis,
  ]
}

# Allow the IaC automation SA to use any KMS key in the key ring for encryption and decryption
resource "google_kms_key_ring_iam_member" "iac" {
  for_each    = google_kms_key_ring.automation
  key_ring_id = each.value.id
  role        = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member      = google_service_account.iac.member

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Create a KMS key solely for external encryption and decryption such as sops operations
resource "google_kms_crypto_key" "sops" {
  for_each = google_kms_key_ring.automation
  name     = format("%s-sops", var.name)
  key_ring = each.value.id
  labels   = var.labels

  depends_on = [
    google_project_service.apis,
  ]
}

# Create a KMS key solely for encrypting bucket objects
resource "google_kms_crypto_key" "gcs" {
  for_each = google_kms_key_ring.automation
  name     = format("%s-gcs", var.name)
  key_ring = each.value.id
  purpose  = "ENCRYPT_DECRYPT"
  labels   = var.labels

  depends_on = [
    google_project_service.apis,
  ]
}

# Allow the default project storage SA to use the state KMS key for encryption and decryption of objects
resource "google_kms_crypto_key_iam_member" "gcs" {
  for_each      = google_kms_crypto_key.gcs
  crypto_key_id = each.value.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = data.google_storage_project_service_account.default.member
  depends_on = [
    google_project_service.apis,
  ]
}

# Create a bucket for automation state; defaults are sane for Terraform but can be overridden as needed.
resource "google_storage_bucket" "state" {
  for_each                    = try(var.gcp_options.create_state_bucket, true) ? { state = var.state_bucket_options } : {}
  project                     = var.project_id
  name                        = format("%s-automation", var.name)
  force_destroy               = try(each.value.force_destroy, true)
  labels                      = var.labels
  location                    = try(each.value.location, "US")
  storage_class               = try(each.value.class, "STANDARD")
  uniform_bucket_level_access = try(each.value.uniform_access, true)
  public_access_prevention    = "enforced"
  versioning {
    enabled = try(each.value.versioning, true)
  }
  dynamic "encryption" {
    for_each = google_kms_crypto_key.gcs
    content {
      default_kms_key_name = encryption.value.id
    }
  }

  depends_on = [
    google_project_service.apis,
    google_kms_crypto_key_iam_member.gcs,
  ]
}

# Make the IaC automation service account an admin of the bootstrapped bucket.
resource "google_storage_bucket_iam_member" "admin" {
  for_each = google_storage_bucket.state
  bucket   = each.value.name
  role     = "roles/storage.admin"
  member   = google_service_account.iac.member

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Ensure the Cloud Deploy execution service account can view and create objects in the bootstrapped bucket.
resource "google_storage_bucket_iam_member" "deploy" {
  for_each = { for i, combo in setproduct([for bucket in google_storage_bucket.state : bucket.name], [for sa in google_service_account.deploy : sa.member], ["roles/storage.objectViewer", "roles/storage.objectCreator"]) : tostring(i) => {
    bucket = combo[0]
    member = combo[1]
    role   = combo[2]
  } }
  bucket = each.value.bucket
  role   = each.value.role
  member = each.value.member

  depends_on = [
    google_project_service.apis,
    google_service_account.deploy,
  ]
}
