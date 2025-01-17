variable "project_id" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id value must be a valid Google Cloud project identifier"
  }
}

variable "name" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}[a-z0-9]$", var.name))
    error_message = "The name variable must be RFC1035 compliant and between 1 and 32 characters in length."
  }
  description = <<-EOD
  The common name to use for resources.
  EOD
}

variable "description" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("", var.description))
    error_message = "The description variable must have a valid value."
  }
  default     = "Google automation on XC"
  description = <<-EOD
  A descriptive value to apply to resources that identify the purpose of the deployment.
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

variable "github" {
  type = object({
    user = string
    pat  = string
    repo = string
  })
  nullable    = false
  description = <<-EOD
  The GitHub configuration for Atlantis.
  EOD
}

variable "domain" {
  type        = string
  nullable    = false
  description = <<-EOD
  The DNS domain name associated in the F5 Distributed Cloud tenant; will be used to provision ingress for services.
  EOD
}

variable "repositories" {
  type     = list(string)
  nullable = true
  validation {
    condition     = var.repositories == null ? true : length(join("", [for repo in var.repositories : can(regex("^(?:(?:(?:asia|eu|us).)?gcr.io|[a-z]{2,}(?:-[a-z]+[1-9])?-docker.pkg.dev/[^/]+/[^/]+)", repo)) ? "x" : ""])) == length(var.repositories)
    error_message = "Each repositories entry must be a valid gcr.io or XXX-docker.pkg.dev repository."
  }
  default     = []
  description = <<-EOD
  An optional list of GCR and/or GAR repositories. If provided, the generated service account will be given the
  appropriate GCR or GAR read-only access role to the repos.
  EOD
}

variable "expiration_days" {
  type     = number
  nullable = false
  validation {
    condition     = floor(var.expiration_days) == var.expiration_days && var.expiration_days >= 0 && var.expiration_days <= 90
    error_message = "The expiration_days value must be an integer between 0 and 90 inclusive."
  }
  default     = 7
  description = <<-EOD
  Used to set the end-of-life for generated kubeconfig and other API authentication tokens. Default is 7, which renders
  generated credentials invalid after 7 days.
  EOD
}
