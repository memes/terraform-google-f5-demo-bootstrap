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

variable "bootstrap_apis" {
  type        = set(string)
  nullable    = false
  default     = []
  description = <<-EOD
  An optional set of Google Cloud APIs to enable during bootstrap, in addition
  to those required for Cloud Deploy resources. Default is an empty set.
  EOD
}

variable "bucket_name" {
  type        = string
  nullable    = true
  default     = null
  description = <<-EOD
    An optional GCS bucket that will be used for Cloud Deploy state.
    EOD
}

variable "options" {
  type = object({
    services_disable_on_destroy = bool
    disable_dependent_services  = bool
  })
  nullable = false
  default = {
    services_disable_on_destroy = false
    disable_dependent_services  = false
  }
}


# tflint-ignore: terraform_unused_declarations
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
