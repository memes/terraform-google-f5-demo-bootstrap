terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.9"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.9"
    }
    tfe = {
      source  = "hashicorp/tfe"
      version = ">= 0.59"
    }
  }
}

locals {
  workload_identity_project_id = regex("projects/([^/]+)/", var.workload_identity_pool_id)[0]
  workload_identity_pool_id    = regex("/([^/]+)$", var.workload_identity_pool_id)[0]
}

data "google_iam_workload_identity_pool" "bootstrap" {
  provider                  = google-beta
  project                   = local.workload_identity_project_id
  workload_identity_pool_id = local.workload_identity_pool_id
}

data "google_project" "bootstrap" {
  project_id = local.workload_identity_project_id
}

resource "tfe_project" "automation" {
  name = var.name
}

# resource "tfe_workspace" "automation" {
#     name = var.name
#     project_id = tfe_project.automation.id
#     description = <<-EOD
#     Bootstrapped automation workspace
#     EOD
#     allow_destroy_plan = true
#     source_name = "strangelambda bootstrap"
#     source_url = "https://github.com/strangelambda/bootstrap"
#     terraform_version = "~> 1.5"
# }

resource "google_iam_workload_identity_pool_provider" "terraform" {
  project                            = data.google_iam_workload_identity_pool.bootstrap.project
  workload_identity_pool_id          = data.google_iam_workload_identity_pool.bootstrap.workload_identity_pool_id
  workload_identity_pool_provider_id = format("%s-tf", var.name)
  display_name                       = "TFC/TFE OIDC provider"
  description                        = <<-EOD
    Defines an OIDC provider that authenticates a Terraform Cloud/TFE token as a valid automation user.
    EOD
  attribute_mapping = {
    "attribute.aud"                         = "assertion.aud",
    "attribute.terraform_run_phase"         = "assertion.terraform_run_phase",
    "attribute.terraform_project_id"        = "assertion.terraform_project_id",
    "attribute.terraform_project_name"      = "assertion.terraform_project_name",
    "attribute.terraform_workspace_id"      = "assertion.terraform_workspace_id",
    "attribute.terraform_workspace_name"    = "assertion.terraform_workspace_name",
    "attribute.terraform_organization_id"   = "assertion.terraform_organization_id",
    "attribute.terraform_organization_name" = "assertion.terraform_organization_name",
    "attribute.terraform_run_id"            = "assertion.terraform_run_id",
    "attribute.terraform_full_workspace"    = "assertion.terraform_full_workspace",
    "google.subject"                        = "assertion.sub"
    "attribute.automation_sa"               = "'enabled'"
  }
  # Only allow integration with workspaces associated with the bootrstrapped project
  attribute_condition = format("attribute.terraform_project_id == '%s'", tfe_project.automation.id)
  oidc {
    # TODO @memes - the effect of an empty list is to impose a match against the
    # fully-qualified workload identity pool name. This should be sufficient but
    # review.
    allowed_audiences = []
    issuer_uri        = "https://app.terraform.io"
  }
}

# Configure a set of environment variables that will configure the Google provider
# to use dynamic credentials and workload identity when attempting to execute as
# the automation service account.
resource "tfe_variable_set" "auth" {
  name         = format("GCP OIDC authentication for %s", var.name)
  description  = "Environment variables to configure Google provider to use OIDC for dynamic authenticate with GCP workload identity."
  organization = tfe_project.automation.organization
}

resource "tfe_variable" "gcp_provider_auth" {
  key             = "TFC_GCP_PROVIDER_AUTH"
  value           = "true"
  category        = "env"
  description     = "Enables dynamic credential support in Google provider."
  variable_set_id = tfe_variable_set.auth.id
}

resource "tfe_variable" "gcp_project_number" {
  key             = "TFC_GCP_PROJECT_NUMBER"
  value           = data.google_project.bootstrap.number
  category        = "env"
  description     = "The GCP project number to use with workload identity authentication."
  variable_set_id = tfe_variable_set.auth.id
}

resource "tfe_variable" "gcp_run_service_account_email" {
  key             = "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL"
  value           = var.service_account
  category        = "env"
  description     = "The automation service account identifier."
  variable_set_id = tfe_variable_set.auth.id
}

resource "tfe_variable" "gcp_workload_pool_id" {
  key             = "TFC_GCP_WORKLOAD_POOL_ID"
  value           = data.google_iam_workload_identity_pool.bootstrap.id
  category        = "env"
  description     = "The GCP workload identity pool identifier."
  variable_set_id = tfe_variable_set.auth.id
}

resource "tfe_variable" "gcp_workload_provider_id" {
  key             = "TFC_GCP_WORKLOAD_PROVIDER_ID"
  value           = google_iam_workload_identity_pool_provider.terraform.workload_identity_pool_provider_id
  category        = "env"
  description     = "The GCP workload identity provider identifier."
  variable_set_id = tfe_variable_set.auth.id
}

resource "tfe_project_variable_set" "auth" {
  project_id      = tfe_project.automation.id
  variable_set_id = tfe_variable_set.auth.id
}

# Configure a set of common Terraform variables that can be used by subsequent
# workspaces.
resource "tfe_variable_set" "common" {
  name         = format("Common tfvars declaration for %s", tfe_project.automation.name)
  description  = "Terraform variables that may be reused by workspaces."
  organization = tfe_project.automation.organization
}

resource "tfe_variable" "var" {
  for_each        = var.variables
  key             = each.key
  value           = each.value
  category        = "terraform"
  variable_set_id = tfe_variable_set.common.id
}

resource "tfe_project_variable_set" "common" {
  project_id      = tfe_project.automation.id
  variable_set_id = tfe_variable_set.common.id
}
