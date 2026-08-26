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
  The common name (and prefix) to use for Google Cloud and GitHub resources (see also `github_options`).
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
  An optional set of key:value string pairs that will be added to Google Cloud resources that accept labels.
  Alternative: Set common labels in the `google` provider configuration.
  EOD
}

variable "project_id" {
  type     = string
  nullable = false
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "The project_id value must be a valid Google Cloud project identifier"
  }
  description = <<-EOD
  The Google Cloud project that will host resources.
  EOD
}

variable "github_options" {
  type = object({
    private_repo       = optional(bool, false)
    name               = optional(string)
    description        = optional(string, "Bootstrapped automation repository")
    template           = optional(string, "memes/terraform-google-f5-demo-bootstrap-template")
    archive_on_destroy = optional(bool, true)
    collaborators      = optional(set(string))
    ssh_deploy_key     = optional(bool, false)
    org                = optional(string)
  })
  nullable = true
  default = {
    private_repo       = false
    name               = ""
    description        = "Bootstrapped automation repository"
    template           = "memes/terraform-google-f5-demo-bootstrap-template"
    archive_on_destroy = true
    collaborators      = []
    ssh_deploy_key     = false
    org                = null
  }
  description = <<-EOD
  Defines the parameters for the GitHub repository to create for the demo. By default the GitHub repo will be public,
  named from the `name` variable and populated from `memes/terraform-google-f5-demo-bootstrap-template` repo. Use this
  variable to override one or more of these defaults as needed.
  EOD
}

variable "gcp_options" {
  type = object({
    enable_infra_manager        = optional(bool, true)
    enable_cloud_deploy         = optional(bool, true)
    services_disable_on_destroy = optional(bool, false)
    disable_dependent_services  = optional(bool, false)
    create_state_bucket         = optional(bool, true)
    ar = optional(object({
      location    = optional(string, "us")
      oci         = optional(bool, true)
      deb         = optional(bool, false)
      rpm         = optional(bool, false)
      docker_hub  = optional(bool, false)
      virtual_oci = optional(bool, false)
    }))
    kms = optional(bool, false)
  })
  nullable = true
  default = {
    enable_infra_manager        = true
    enable_cloud_deploy         = true
    services_disable_on_destroy = false
    disable_dependent_services  = false
    create_state_bucket         = true
    ar = {
      location    = "us"
      oci         = true
      deb         = false
      rpm         = false
      docker_hub  = false
      virtual_oci = false
    }
    kms = false
  }
  description = <<-EOD
  Defines the parameters for the supporting Google Cloud resources that may not be essential to the demo. By default
  service accounts and resources to support Infrastructure Manager (managed Terraform IaC) and Cloud Deploy (managed GKE
  and Cloud Run deployments) are created, along with a US Cloud Storage bucket to contain the Terraform state. An
  Artifact Repository will be created for OCI containers, but not DEB or RPM repos. Use this variable to override one or
  more of these defaults as needed. If the flag for virtual OCI repository is set, the local OCI registry, docker hub,
  and one or both of NGINX private repository and F5 AI private repository will be added to the virtual server, with
  highest priority assigned in that order.
  EOD
}

variable "bootstrap_apis" {
  type        = set(string)
  nullable    = true
  default     = []
  description = <<-EOD
  An optional set of Google Cloud APIs to enable during bootstrap, in addition
  to those required for bootstrap resources. Default is an empty set.
  EOD
}

variable "iac_roles" {
  type        = set(string)
  nullable    = true
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

variable "nginx_jwt" {
  type     = string
  nullable = true
  validation {
    condition     = try(length(var.nginx_jwt), 0) == 0 ? true : can(regex("^(?:\\.?(?:[A-Za-z0-9_-]+)){3}$", var.nginx_jwt))
    error_message = "The nginx_jwt value must be null/empty or a valid JWT token."
  }
  default     = null
  description = <<-EOD
  An optional NGINX+ JWT to store in Google Secret Manager. If provided, a remote Artifact Registry will be created to
  reference the upstream NGINX private Docker repository for transparent access to the private images.
  NOTE: Principal access to the secret will not be established by this module; module consumers will be required to
  assign the appropriate IAM roles to read or modify the secret as needed.
  EOD
}

variable "cloud_deploy_roles" {
  type        = set(string)
  nullable    = true
  default     = []
  description = <<-EOD
  An optional set of IAM roles to assign to the Cloud Deploy automation service account, if it is created. Default is an
  empty set.
  E.g. to support deploying to GKE:
  cloud_deploy_roles = [
    "roles/container.developer",
  ]
  EOD
}

variable "iac_options" {
  type = object({
    enable_workload_identity_pool_admin = optional(bool, false)
  })
  nullable    = true
  default     = null
  description = <<-EOD
  An optional set of flags to apply to the IaC account.
  EOD
}


variable "state_bucket_options" {
  type = object({
    class          = optional(string, "STANDARD")
    location       = optional(string, "US")
    force_destroy  = optional(bool, true)
    uniform_access = optional(bool, true)
    versioning     = optional(bool, true)
  })
  nullable = true
  default = {
    class          = "STANDARD"
    location       = "US"
    force_destroy  = true
    uniform_access = true
    versioning     = true
  }
  description = <<-EOD
  Defines the parameters for the IaC GCS state bucket, if enabled in gcp_options.
  EOD
}

variable "f5_ai_repo_credentials" {
  type = object({
    username = string
    password = string
  })
  nullable = true
  validation {
    condition     = var.f5_ai_repo_credentials == null ? true : try(length(compact([var.f5_ai_repo_credentials.username, var.f5_ai_repo_credentials.password])), 0) == 2
    error_message = "If not null, f5_ai_repo_credentials must have non-empty username and password fields."
  }
  default     = null
  description = <<-EOD
  An optional username and password pair for the upstream F5 AI container repository. If provided, a remote Artifact
  Registry will be created to reference the upstream F5 AI private repository for transparent access to the
  private images, along with a Secret Manager secret to contain the password.
  EOD
}

variable "secrets" {
  type     = map(string)
  nullable = true
  validation {
    # Keys become secret names when combined with name variable as '{name}-{key}', with a maximum limit of 255 combined chars.
    condition     = try(length(var.secrets), 0) == 0 ? true : alltrue([for k, v in var.secrets : can(regex("^[a-zA-Z0-9_-]{1,228}$", k))])
    error_message = "Each secrets entry key must be alphanumeric, underscore, or hyphen, with a maximum length of 228."
  }
  default     = null
  description = <<-EOD
  An optional map of Secret names to values (strings-only) that will be created. A Secret Manager secret will be created
  for each key in the map, and a GitHub actions variable of the form `{KEY_NAME}_SECRET` containing the Secret Manager
  identity. The value must be a string; use `jsonencode` or similar to include structured or binary data.
  NOTE: Values are allowed to be null/empty.
  NOTE 2: The input variables `nginx_jwt` and `f5_ai_repo_credentials` are preferred for those secrets, as they will
  trigger creation of Artifact Registries. Avoid using the same value in both places, but use `secrets` input if you
  want to store either of those without triggering creation of supporting resources.
  EOD
}
