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
