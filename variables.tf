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

variable "options" {
  type = object({
    services_disable_on_destroy = bool
    disable_dependent_services  = bool
    bucket_class                = string
    bucket_location             = string
    bucket_force_destroy        = bool
    bucket_uniform_access       = bool
    bucket_versioning           = bool
    private_repo                = bool
    ar = object({
      location = string
      oci      = bool
      deb      = bool
      rpm      = bool
    })
    repo_description = string
    repo_name        = string
  })
  nullable = false
  default = {
    services_disable_on_destroy = false
    disable_dependent_services  = false
    bucket_class                = "STANDARD"
    bucket_location             = "US"
    bucket_force_destroy        = true
    bucket_uniform_access       = true
    bucket_versioning           = true
    private_repo                = false
    ar = {
      location = "us"
      oci      = true
      deb      = false
      rpm      = false
    }
    repo_description = "Bootstrapped automation repository"
    repo_name        = ""
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

variable "automation_roles" {
  type        = set(string)
  nullable    = false
  default     = []
  description = <<-EOD
  An optional set of IAM roles to assign to the automation service account.
  Default is an empty set.
  EOD
}

variable "impersonators" {
  type     = list(string)
  nullable = true
  validation {
    condition     = var.impersonators == null ? true : alltrue([for impersonator in var.impersonators : can(regex("^(?:user|group|serviceAccount):", impersonator))])
    error_message = "The impersonators variable must be empty or contain valid IAM accounts."
  }
  default     = []
  description = <<-EOD
  A list of fully-qualified IAM accounts that will be allowed to impersonate the automation service account. If no
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

variable "template_repo" {
  type = object({
    owner = string
    repo  = string
  })
  validation {
    # If not null, owner and repo are required to be set to non-empty values
    condition     = var.template_repo == null ? true : trimspace(var.template_repo.owner) != "" && trimspace(var.template_repo.repo) != ""
    error_message = "The template_repo variable must include valid owner and repo values."
  }
  nullable = true
  default  = null
}
