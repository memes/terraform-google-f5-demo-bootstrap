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
  ar_repos = merge(
    try(var.gcp_options.ar.oci, true) ? {
      oci = {
        name        = format("%s-oci", var.name)
        format      = "DOCKER"
        description = format("OCI registry for %s", var.name)
        location    = try(var.gcp_options.ar.location, "us")
        identifier  = format("%s-docker.pkg.dev/%s/%s-oci", try(var.gcp_options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
    try(var.gcp_options.ar.deb, false) ? {
      deb = {
        name        = format("%s-deb", var.name)
        format      = "APT"
        description = format("deb package registry for %s", var.name)
        location    = try(var.gcp_options.ar.location, "us")
        identifier  = format("ar+https://%s-apt.pkg.dev/projects/%s %s-deb main", try(var.gcp_options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
    try(var.gcp_options.ar.rpm, false) ? {
      rpm = {
        name        = format("%s-rpm", var.name)
        format      = "YUM"
        description = format("rpm package registry for %s", var.name)
        location    = try(var.gcp_options.ar.location, "us")
        identifier  = format("https://%s-yum.pkg.dev/projects/%s/%s-rpm", try(var.gcp_options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
  )
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
  display_name              = "Automation pool"
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

# Create any needed artifact registry for the project
resource "google_artifact_registry_repository" "automation" {
  for_each      = local.ar_repos
  project       = var.project_id
  repository_id = each.value.name
  format        = each.value.format
  location      = try(var.gcp_options.ar.location, "us")
  description   = each.value.description
  labels        = var.labels

  depends_on = [
    google_project_service.apis,
  ]
}

# Allow the IaC automation service account admin access to the repos.
resource "google_artifact_registry_repository_iam_member" "iac" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.admin"
  member     = google_service_account.iac.member

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Allow OIDC principals with attribute 'artifact_registry="writer"' read-only access to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "reader" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.reader"
  member     = format("principalSet://iam.googleapis.com/%s/attribute.artifact_registry/reader", google_iam_workload_identity_pool.bots.name)

  depends_on = [
    google_project_service.apis,
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC principals with attribute 'artifact_registry="writer"' push access to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "writer" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.writer"
  member     = format("principalSet://iam.googleapis.com/%s/attribute.artifact_registry/writer", google_iam_workload_identity_pool.bots.name)

  depends_on = [
    google_project_service.apis,
    google_iam_workload_identity_pool.bots,
  ]
}

# This creates the service account that may be used by CI services that need to write to registry without requiring full IaC access.
resource "google_service_account" "ar" {
  project      = var.project_id
  account_id   = format("%s-ar", var.name)
  display_name = "Artifact Registry automation service account"
  description  = <<-EOD
  Service account that may be used by various automation providers that need to write to Artifact Registry.
  EOD

  depends_on = [
    google_project_service.apis,
  ]
}

# Bind the workload identity user role on Artifact Registry service account for principals that satisfy the condition that their respective provider has the
# custom 'ar_sa' attribute set to true.
resource "google_service_account_iam_member" "ar" {
  service_account_id = google_service_account.ar.name
  member             = format("principalSet://iam.googleapis.com/%s/attribute.ar_sa/enabled", google_iam_workload_identity_pool.bots.name)
  role               = "roles/iam.workloadIdentityUser"

  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC principals with attribute 'artifact_registry="writer"' push access to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "ar" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.ar.member

  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
    google_iam_workload_identity_pool.bots,
  ]
}

# Bootstraps a new GitHub repository with the required settings for automation.
resource "github_repository" "automation" {
  name        = coalesce(try(var.github_options.name, ""), var.name)
  description = var.github_options.description
  visibility  = try(var.github_options.private_repo, false) ? "private" : "public"
  dynamic "template" {
    for_each = coalesce(try(var.github_options.template, ""), "unspecified") == "unspecified" ? {} : { template = { owner = reverse(split("/", var.github_options.template))[1], name = reverse(split("/", var.github_options.template))[0] } }
    content {
      owner                = template.value.owner
      repository           = template.value.repo
      include_all_branches = false
    }
  }

  # Prevent deletion of the repo during post-demo cleanup
  lifecycle {
    prevent_destroy = true
  }
}

# Invite collaborators to the new repo
resource "github_repository_collaborator" "collaborators" {
  for_each   = var.collaborators
  repository = github_repository.automation.name
  permission = "push"
  username   = each.value

  # Prevent deletion of the repo during post-demo cleanup
  lifecycle {
    prevent_destroy = true
  }
}

# Create a deploy key
resource "tls_private_key" "automation" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "github_repository_deploy_key" "automation" {
  repository = github_repository.automation.name
  title      = "Automation deploy key"
  key        = tls_private_key.automation.public_key_openssh
  read_only  = false
}

# Bind the new repo as an OIDC provider for automation.
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.bots.workload_identity_pool_id
  workload_identity_pool_provider_id = format("%s-gh", var.name)
  display_name                       = "GitHub OIDC provider"
  description                        = <<-EOD
  Defines an OIDC provider that authenticates a GitHub token as a valid automation user.
  EOD
  attribute_mapping = {
    "attribute.actor"            = "assertion.actor"
    "attribute.aud"              = "assertion.aud"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "google.subject"             = "assertion.sub"
    "attribute.ar_sa"            = "'enabled'"
    "attribute.infra_manager"    = "'enabled'"
    "attribute.cloud_deploy"     = "'enabled'"
  }
  # Only allow integration with the bootstrapped repo
  attribute_condition = format("attribute.repository_owner == '%s' && attribute.repository == '%s'", split("/", github_repository.automation.full_name)[0], github_repository.automation.full_name)
  oidc {
    # TODO @memes - the effect of an empty list is to impose a match against the
    # fully-qualified workload identity pool name. This should be sufficient but
    # review.
    allowed_audiences = []
    issuer_uri        = "https://token.actions.githubusercontent.com"
  }
  depends_on = [
    google_project_service.apis,
  ]
}

resource "github_actions_secret" "provider_id" {
  repository      = github_repository.automation.name
  secret_name     = "WORKLOAD_IDENTITY_PROVIDER_ID"
  plaintext_value = google_iam_workload_identity_pool_provider.github.name
}

resource "github_actions_secret" "iac_sa" {
  repository      = github_repository.automation.name
  secret_name     = "IAC_SERVICE_ACCOUNT"
  plaintext_value = google_service_account.iac.email

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

resource "github_actions_secret" "ar_sa" {
  repository      = github_repository.automation.name
  secret_name     = "AR_SERVICE_ACCOUNT"
  plaintext_value = google_service_account.ar.email

  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
  ]
}

resource "github_actions_secret" "deploy_sa" {
  for_each        = google_service_account.deploy
  repository      = github_repository.automation.name
  secret_name     = "DEPLOY_SERVICE_ACCOUNT"
  plaintext_value = each.value.email

  depends_on = [
    google_project_service.apis,
    google_service_account.deploy,
  ]
}

resource "github_actions_variable" "project_id" {
  repository    = github_repository.automation.name
  variable_name = "PROJECT_ID"
  value         = var.project_id
}

resource "github_actions_variable" "registry" {
  for_each      = { for k, v in google_artifact_registry_repository.automation : format("%s_REGISTRY", upper(k)) => local.ar_repos[k].identifier }
  repository    = github_repository.automation.name
  variable_name = each.key
  value         = each.value
}
