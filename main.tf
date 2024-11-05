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
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

data "google_project" "project" {
  project_id = var.project_id
}

data "google_storage_project_service_account" "default" {
  project = var.project_id
}

locals {
  ar_repos = merge(
    try(var.options.ar.oci, true) ? {
      oci = {
        name        = format("%s-oci", var.name)
        format      = "DOCKER"
        description = format("OCI registry for %s", var.name)
        location    = try(var.options.ar.location, "us")
        identifier  = format("%s-docker.pkg.dev/%s/%s-oci", try(var.options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
    try(var.options.ar.deb, false) ? {
      deb = {
        name        = format("%s-deb", var.name)
        format      = "APT"
        description = format("deb package registry for %s", var.name)
        location    = try(var.options.ar.location, "us")
        identifier  = format("ar+https://%s-apt.pkg.dev/projects/%s %s-deb main", try(var.options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
    try(var.options.ar.rpm, false) ? {
      rpm = {
        name        = format("%s-rpm", var.name)
        format      = "YUM"
        description = format("rpm package registry for %s", var.name)
        location    = try(var.options.ar.location, "us")
        identifier  = format("https://%s-yum.pkg.dev/projects/%s/%s-rpm", try(var.options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
  )
}

# Bootstrapping should enable the minimal set of services required to complete
# bootstrap and permit additional actions to be executed.
resource "google_project_service" "apis" {
  for_each = { for api in setunion([
    "artifactregistry.googleapis.com",
    "cloudkms.googleapis.com",
    "containerscanning.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage-api.googleapis.com",
    "sts.googleapis.com",
  ], var.bootstrap_apis) : api => true }
  project                    = var.project_id
  service                    = each.key
  disable_on_destroy         = var.options.services_disable_on_destroy
  disable_dependent_services = var.options.disable_dependent_services
}

# This creates the main service account that is used by automations; it is
# analogous to the long-lived Terraform and/or Ansible service accounts I used
# previously.
resource "google_service_account" "automation" {
  project      = var.project_id
  account_id   = format("%s-bot", var.name)
  display_name = "General purpose automation service account"
  description  = <<-EOD
  Service account that will be used by various automation providers (GitHub, Terraform, etc) to stand-up Google Cloud resources.
  EOD

  depends_on = [
    google_project_service.apis,
  ]
}

# Bind service account to project roles, as needed.
resource "google_service_account_iam_member" "impersonation" {
  for_each = { for i, pair in setproduct(var.impersonators, ["roles/iam.serviceAccountTokenCreator", "roles/iam.serviceAccountUser"]) : "${i}" => {
    member = pair[0]
    role   = pair[1]
  } }
  service_account_id = google_service_account.automation.name
  member             = each.value.member
  role               = each.value.role
}

# Bind the automation service account to the necessary project roles.
resource "google_project_iam_member" "automation" {
  for_each = var.automation_roles
  project  = var.project_id
  role     = each.key
  member   = google_service_account.automation.member

  depends_on = [
    google_project_service.apis,
    google_service_account.automation,
  ]
}

# Bootstrap the workload identity pool that is associated with this deployment
# repo. This allows short lived OIDC tokens to be authenticated and used for
# invoking APIs as the automation service account.
resource "google_iam_workload_identity_pool" "automation" {
  project                   = var.project_id
  workload_identity_pool_id = format("%s-bot", var.name)
  display_name              = "Automation pool"
  description               = <<-EOD
  Defines a pool of third-party providers that can exchange tokens for automation actions.
  EOD
  disabled                  = false

  depends_on = [
    google_project_service.apis,
  ]
}

# Bind the workload identity user role on automation service account for principals
# that satisfy the condition that their respective provider has the custom
# 'automation_sa' attribute set to true.
resource "google_service_account_iam_member" "automation" {
  service_account_id = google_service_account.automation.name
  member             = format("principalSet://iam.googleapis.com/%s/attribute.automation_sa/enabled", google_iam_workload_identity_pool.automation.name)
  role               = "roles/iam.workloadIdentityUser"
}

# Create a KMS key ring for use by automation modules
resource "google_kms_key_ring" "automation" {
  project  = var.project_id
  name     = format("%s-automation", var.name)
  location = try(lower(var.options.bucket_location), "global")
  depends_on = [
    google_project_service.apis,
  ]
}

# Allow the automation SA to use any KMS key in the key ring for encryption and decryption
resource "google_kms_key_ring_iam_member" "automation" {
  key_ring_id = google_kms_key_ring.automation.id
  role        = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member      = google_service_account.automation.member

  depends_on = [
    google_project_service.apis,
    google_service_account.automation,
  ]
}

# Create a KMS key solely for external encryption and decryption such as sops operations
resource "google_kms_crypto_key" "sops" {
  name     = format("%s-sops", var.name)
  key_ring = google_kms_key_ring.automation.id
  purpose  = "ENCRYPT_DECRYPT"
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
  force_destroy               = try(var.options.bucket_force_destroy, true)
  labels                      = var.labels
  location                    = try(var.options.bucket_location, "US")
  storage_class               = try(var.options.bucket_class, "STANDARD")
  uniform_bucket_level_access = try(var.options.bucket_uniform_access, true)
  public_access_prevention    = "enforced"
  versioning {
    enabled = try(var.options.bucket_versioning, false)
  }
  encryption {
    default_kms_key_name = google_kms_crypto_key.gcs.id
  }

  depends_on = [
    google_project_service.apis,
    google_kms_crypto_key_iam_member.gcs,
  ]
}

# Make the automation service account an admin of the bootstrapped bucket.
resource "google_storage_bucket_iam_member" "admin" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.admin"
  member = google_service_account.automation.member

  depends_on = [
    google_project_service.apis,
    google_service_account.automation,
  ]
}

# Create any needed artifact registry for the project, and assign the automation service account as an admin
resource "google_artifact_registry_repository" "automation" {
  for_each      = local.ar_repos
  project       = var.project_id
  repository_id = each.value.name
  format        = each.value.format
  location      = try(var.options.ar.location, "us")
  description   = each.value.description
  labels        = var.labels

  depends_on = [
    google_project_service.apis,
  ]
}

resource "google_artifact_registry_repository_iam_member" "automation" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.repoAdmin"
  member     = google_service_account.automation.member

  depends_on = [
    google_project_service.apis,
    google_service_account.automation,
  ]
}

# Bootstraps a new GitHub repository with the required settings for automation.
resource "github_repository" "automation" {
  name        = var.name
  description = var.options.repo_description
  visibility  = var.options.private_repo ? "private" : "public"
  dynamic "template" {
    for_each = var.template_repo == null ? {} : { template = var.template_repo }
    content {
      owner                = template.value.owner
      repository           = template.value.repo
      include_all_branches = false
    }
  }
}

# Invite collaborators to the new repo
resource "github_repository_collaborator" "collaborators" {
  for_each   = var.collaborators
  repository = github_repository.automation.name
  permission = "push"
  username   = each.value
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
  workload_identity_pool_id          = google_iam_workload_identity_pool.automation.workload_identity_pool_id
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
    "attribute.automation_sa"    = "'enabled'"
  }
  # Only allow integration with the bootstrapped repo
  attribute_condition = format("attribute.repository_owner == '%s' && attribute.repository == '%s'", split("/", github_repository.automation.full_name)...)
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

resource "github_actions_secret" "automation_sa" {
  repository      = github_repository.automation.name
  secret_name     = "SERVICE_ACCOUNT"
  plaintext_value = google_service_account.automation.email

  depends_on = [
    google_project_service.apis,
    google_service_account.automation,
  ]
}

resource "github_actions_variable" "registry" {
  for_each      = { for k, v in google_artifact_registry_repository.automation : format("%s_REGISTRY", upper(k)) => local.ar_repos[k].identifier }
  repository    = github_repository.automation.name
  variable_name = each.key
  value         = each.value
}
