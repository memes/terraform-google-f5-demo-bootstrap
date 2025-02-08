terraform {
  required_version = ">= 1.5"
  required_providers {
    f5xc = {
      source  = "registry.terraform.io/memes/f5xc"
      version = ">= 0.1"
    }
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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.33"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
    volterra = {
      source  = "volterraedge/volterra"
      version = ">= 0.11.39"
    }
  }
}

# Configured in .envrc: GITHUB_TOKEN and GITHUB_OWNER
provider "github" {}

# Configured in .envrc: VOLT_API_*
provider "volterra" {}

# Configured in .envrc: VOLT_API_*
provider "f5xc" {}

module "bootstrap" {
  source     = "../../"
  project_id = var.project_id
  name       = var.name
  options = {
    services_disable_on_destroy = false
    disable_dependent_services  = false
    bucket_class                = "STANDARD"
    bucket_location             = "US"
    bucket_force_destroy        = true
    bucket_uniform_access       = true
    bucket_versioning           = false
    private_repo                = true
    ar_location                 = "us"
    ar = {
      location = "us"
      oci      = true
      deb      = false
      rpm      = false
    }
    repo_description = "Test repo"
  }
  labels = var.gcp_labels
  collaborators = [
    var.github.user,
  ]
  bootstrap_apis   = var.bootstrap_apis
  automation_roles = var.automation_roles
  impersonators    = var.impersonators
}

module "vk8s" {
  source     = "../../modules/re-vk8s/"
  name       = var.name
  project_id = var.project_id
  namespace  = var.namespace
  github = {
    user = var.github.user
    pat  = var.github.pat
    repo = module.bootstrap.github_repo
  }
  labels      = var.labels
  annotations = var.annotations
  region      = var.region
  domain      = format("%s.%s", var.name, var.domain)
}

# TODO @memes - I think there's a reason this is needed for k8s. Take another look at this sometime.
# tflint-ignore: terraform_unused_declarations
data "google_client_openid_userinfo" "provider" {}

data "google_service_account" "bootstrap" {
  account_id = regex("^([^@]+)@", module.bootstrap.sa)[0]
  project    = regex("@([^\\.]+)\\.", module.bootstrap.sa)[0]
}

data "google_service_account" "vk8s" {
  account_id = regex("^([^@]+)@", module.vk8s.sa)[0]
  project    = regex("@([^\\.]+)\\.", module.vk8s.sa)[0]
}

# Allow the vk8s service account to impersonate the bootstrap service account
resource "google_service_account_iam_member" "automation" {
  service_account_id = data.google_service_account.bootstrap.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = data.google_service_account.vk8s.member
}

resource "google_artifact_registry_repository_iam_member" "automation" {
  for_each   = module.bootstrap.registries
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.reader"
  member     = data.google_service_account.vk8s.member
}


resource "local_sensitive_file" "kubeconfig" {
  filename             = format("%s/%s.kubeconfig", path.module, var.name)
  file_permission      = "0640"
  directory_permission = "0755"
  content              = module.vk8s.kubeconfig
}
