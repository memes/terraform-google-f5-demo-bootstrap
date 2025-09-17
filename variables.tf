variable "name" {
  type     = string
  nullable = false
  validation {
    # The generated service account names has a limit of 30 characters, including
    # the '-bot' suffix. Validate that var.name is 1 <= length(var.name) <=26.
    condition     = can(regex("^[a-z][a-z0-9-]{0,24}[a-z0-9]$", var.name))
    error_message = "The name variable must be RFC1035 compliant and between 1 and 26 characters in length."
  }
  description = <<-EOD
  The common name to use for resources.
  EOD
}

variable "labels" {
  type     = map(string)
  nullable = true
  validation {
    # GCP resource labels must be lowercase alphanumeric, underscore or hyphen,
    # and the key must be <= 63 characters in length
    condition     = length(compact([for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v)) ? "x" : ""])) == length(keys(var.labels))
    error_message = "Each label key:value pair must match GCP requirements."
  }
  default     = {}
  description = <<-EOD
  An optional set of key:value string pairs that will be added to GCP resources
  that accept labels.
  EOD
}

variable "project_id" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id value must be a valid Google Cloud project identifier"
  }
}

variable "github_options" {
  type = object({
    private_repo       = bool
    name               = optional(string)
    description        = optional(string)
    template           = optional(string)
    archive_on_destroy = optional(bool, true)
  })
  nullable = false
  default = {
    private_repo       = false
    name               = ""
    description        = "Bootstrapped automation repository"
    template           = "memes/terraform-google-f5-demo-bootstrap-template"
    archive_on_destroy = true
  }
}

variable "gcp_options" {
  type = object({
    enable_infra_manager        = bool
    enable_cloud_deploy         = bool
    services_disable_on_destroy = bool
    disable_dependent_services  = bool
    bucket = object({
      class          = string
      location       = string
      force_destroy  = bool
      uniform_access = bool
      versioning     = bool
    })
    ar = object({
      location = string
      oci      = bool
      deb      = bool
      rpm      = bool
    })
  })
  nullable = false
  default = {
    enable_infra_manager        = true
    enable_cloud_deploy         = true
    services_disable_on_destroy = false
    disable_dependent_services  = false
    bucket = {
      class          = "STANDARD"
      location       = "US"
      force_destroy  = true
      uniform_access = true
      versioning     = true
    }
    ar = {
      location = "us"
      oci      = true
      deb      = false
      rpm      = false
    }
  }
}

variable "bootstrap_apis" {
  type        = set(string)
  nullable    = false
  default     = []
  description = <<-EOD
  An optional set of Google Cloud APIs to enable during bootstrap, in addition
  to those required for bootstrap resources. Default is an empty set.
  EOD
}

variable "iac_roles" {
  type        = set(string)
  nullable    = false
  default     = []
  description = <<-EOD
  An optional set of IAM roles to assign to the IaC automation service account.
  Default is an empty set.
  EOD
}

variable "iac_impersonators" {
  type     = list(string)
  nullable = true
  validation {
    condition     = var.iac_impersonators == null ? true : alltrue([for impersonator in var.iac_impersonators : can(regex("^(?:user|group|serviceAccount):", impersonator))])
    error_message = "The iac_impersonators variable must be empty or contain valid IAM accounts."
  }
  default     = []
  description = <<-EOD
  A list of fully-qualified IAM accounts that will be allowed to impersonate the IaC automation service account. If no
  accounts are supplied, impersonation will not be setup by the script.
  E.g.
  impersonators = [
    "group:devsecops@example.com",
    "group:admins@example.com",
    "user:jane@example.com",
    "serviceAccount:ci-cd@project.iam.gserviceaccount.com",
  ]
  EOD
}

variable "collaborators" {
  type        = set(string)
  nullable    = false
  default     = []
  description = <<-EOD
  An optional set of GitHub users that will be invited to collaborate on the created repo.
  EOD
}

variable "nginx_jwt" {
  type        = string
  nullable    = true
  default     = null
  description = <<-EOD
  An optional NGINX+ JWT to store in Google Secret Manager, with read-only access granted to AR service account.
  EOD
}
