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

variable "project_id" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id value must be a valid Google Cloud project identifier"
  }
}

variable "gcp_labels" {
  type     = map(string)
  nullable = true
  validation {
    # GCP resource labels must be lowercase alphanumeric, underscore or hyphen,
    # and the key must be <= 63 characters in length
    condition     = length(compact([for k, v in var.gcp_labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v)) ? "x" : ""])) == length(keys(var.gcp_labels))
    error_message = "Each gcp_label key:value pair must match GCP requirements."
  }
  default     = {}
  description = <<-EOD
  An optional set of key:value string pairs that will be added to GCP resources
  that accept labels.
  EOD
}

variable "namespace" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-zA-Z0-9]?$", var.namespace))
    error_message = "The namespace variable must be a valid RFC1123 DNS label."
  }
  description = <<-EOD
  The F5 Distributed Cloud namespace to use for vk8s resources.
  EOD
}

variable "labels" {
  type     = map(string)
  nullable = false
  validation {
    # XC labels keys must have keys that match [prefix/]name, where name is a
    # valid DNS label, and prefix is an optional valid DNS domain with <= 253
    # characters.
    condition     = var.labels == null ? true : length(compact([for k, v in var.labels : can(regex("^(?:(?:[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.)+[a-zA-Z]{2,63}/)?[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$", k)) && can(regex("^(?:[^/]{1,253}/)?[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", k)) && can(regex("^(?:[A-Za-z0-9][-A-Za-z0-9_.]{0,126})?[A-Za-z0-9]$", v)) ? "x" : ""])) == length(keys(var.labels))
    error_message = "Each label key:value pair must match expectations."
  }
  default     = {}
  description = <<-EOD
  An optional set of key:value string pairs that will be added generated XC resources.
  EOD
}

variable "annotations" {
  type     = map(string)
  nullable = false
  validation {
    # Kubernetes annotations must have keys are [prefix/]name, where name is a
    # valid DNS label, and prefix is a valid DNS domain with <= 253 characters.
    # Values are not restricted; total combined of all keys and values <= 256Kb
    # which is not a feasible Terraform validation rule.
    condition     = var.annotations == null ? true : length(compact([for k, v in var.annotations : can(regex("^(?:(?:[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\\.)+[a-zA-Z]{2,63}/)?[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$", k)) && can(regex("^(?:[^/]{1,253}/)?[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", k)) ? "x" : ""])) == length(keys(var.annotations))
    error_message = "Each annotation key:value pair must match expectations."
  }
  default     = {}
  description = <<-EOD
  An optional set of key:value annotations that will be added to generated XC resources.
  EOD
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

variable "github" {
  type = object({
    user = string
    pat  = string
  })
  nullable    = false
  description = <<-EOD
  The GitHub configuration for Atlantis.
  EOD
}

variable "region" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^ves-io-[a-z]+$", var.region))
    error_message = "The region value must match ves-io-[a-z]+."
  }
  description = <<-EOD
  The F5 Distributed Cloud region where Atlantis will be deployed. Must be of the form `ves-io-*`, e.g. `ves-io-sanjose`.
  EOD
}

variable "domain" {
  type        = string
  nullable    = false
  description = <<-EOD
  The DNS domain name associated in the F5 Distributed Cloud tenant; will be used to provision ingress for services.
  EOD
}
