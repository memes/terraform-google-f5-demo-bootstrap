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

variable "workload_identity_pool_id" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^projects/[a-z][a-z0-9-]{4,28}[a-z0-9]/locations/global/workloadIdentityPools/[a-z0-9-]{4,32}$", var.workload_identity_pool_id))
    error_message = "The workload_identity_pool_id variable must match expected format."
  }
  description = <<-EOD
  The fully-qualified Workload Identity pool identifier.
  EOD
}

variable "service_account" {
  type        = string
  nullable    = false
  description = <<-EOD
    The service account email that will be used for TFC/TFE integration.
    EOD
}

variable "variables" {
  type        = map(string)
  nullable    = false
  default     = {}
  description = <<-EOD
    An optional map of key:value pairs to add as a common Terraform variable set for workspaces.
    EOD
}
