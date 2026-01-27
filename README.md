#

![GitHub release](https://img.shields.io/github/v/release/memes/f5-google-demo-bootstrap?sort=semver)
![Maintenance](https://img.shields.io/maintenance/yes/2026)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)

This Terraform module creates an opinionated automation for an F5 on GCP demo.

<!-- markdownlint-disable MD033 MD034 MD060 -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_github"></a> [github](#requirement\_github) | >= 6.3 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.9 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 6.9 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_nginx_jwt"></a> [nginx\_jwt](#module\_nginx\_jwt) | memes/secret-manager/google | 2.2.2 |

## Resources

| Name | Type |
|------|------|
| [github_actions_secret.ar_sa](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_secret.deploy_sa](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_secret.iac_sa](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_secret.provider_id](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_variable.nginx_jwt](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_actions_variable.project_id](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_actions_variable.registry](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_repository.automation](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository) | resource |
| [github_repository_collaborator.collaborators](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_collaborator) | resource |
| [github_repository_deploy_key.automation](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_deploy_key) | resource |
| [google-beta_google_project_service_identity.ids](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_artifact_registry_repository.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository_iam_member.ar](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.iac](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_iam_workload_identity_pool.bots](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_kms_crypto_key.gcs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key) | resource |
| [google_kms_crypto_key.sops](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key) | resource |
| [google_kms_crypto_key_iam_member.gcs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_kms_key_ring.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_key_ring) | resource |
| [google_kms_key_ring_iam_member.iac](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_key_ring_iam_member) | resource |
| [google_project_iam_member.cloud_deploy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.deploy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.iac](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_iam_member.infra_manager](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_service.apis](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_service_account.ar](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.deploy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account.iac](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.ar](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.deploy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.deploy_cloud_deploy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.iac](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.iac_impersonation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.iac_infra_manager](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket.state](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.admin](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [google_storage_bucket_iam_member.deploy](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [tls_private_key.automation](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [google_storage_project_service_account.default](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | The common name (and prefix) to use for Google Cloud and GitHub resources (see also `github_options`). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The Google Cloud project that will host resources. | `string` | n/a | yes |
| <a name="input_bootstrap_apis"></a> [bootstrap\_apis](#input\_bootstrap\_apis) | An optional set of Google Cloud APIs to enable during bootstrap, in addition<br/>to those required for bootstrap resources. Default is an empty set. | `set(string)` | `[]` | no |
| <a name="input_gcp_options"></a> [gcp\_options](#input\_gcp\_options) | Defines the parameters for the supporting Google Cloud resources that may not be essential to the demo. By default<br/>service accounts and resources to support Infrastructure Manager (managed Terraform IaC) and Cloud Deploy (managed GKE<br/>and Cloud Run deployments) are created, along with a US Cloud Storage bucket to contain the Terraform state. An<br/>Artifact Repository will be created for OCI containers, but not DEB or RPM repos. Use this variable to override one or<br/>more of these defaults as needed. | <pre>object({<br/>    enable_infra_manager        = optional(bool, true)<br/>    enable_cloud_deploy         = optional(bool, true)<br/>    services_disable_on_destroy = optional(bool, false)<br/>    disable_dependent_services  = optional(bool, false)<br/>    bucket = optional(object({<br/>      class          = string<br/>      location       = string<br/>      force_destroy  = bool<br/>      uniform_access = bool<br/>      versioning     = bool<br/>    }))<br/>    ar = optional(object({<br/>      location = string<br/>      oci      = bool<br/>      deb      = bool<br/>      rpm      = bool<br/>    }))<br/>    kms = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "ar": {<br/>    "deb": false,<br/>    "location": "us",<br/>    "oci": true,<br/>    "rpm": false<br/>  },<br/>  "bucket": {<br/>    "class": "STANDARD",<br/>    "force_destroy": true,<br/>    "location": "US",<br/>    "uniform_access": true,<br/>    "versioning": true<br/>  },<br/>  "disable_dependent_services": false,<br/>  "enable_cloud_deploy": true,<br/>  "enable_infra_manager": true,<br/>  "kms": false,<br/>  "services_disable_on_destroy": false<br/>}</pre> | no |
| <a name="input_github_options"></a> [github\_options](#input\_github\_options) | Defines the parameters for the GitHub repository to create for the demo. By default the GitHub repo will be public,<br/>named from the `name` variable and populated from `memes/terraform-google-f5-demo-bootstrap-template` repo. Use this<br/>variable to override one or more of these defaults as needed. | <pre>object({<br/>    private_repo       = bool<br/>    name               = optional(string)<br/>    description        = optional(string)<br/>    template           = optional(string)<br/>    archive_on_destroy = optional(bool, true)<br/>    collaborators      = optional(set(string))<br/>  })</pre> | <pre>{<br/>  "archive_on_destroy": true,<br/>  "collaborators": [],<br/>  "description": "Bootstrapped automation repository",<br/>  "name": "",<br/>  "private_repo": false,<br/>  "template": "memes/terraform-google-f5-demo-bootstrap-template"<br/>}</pre> | no |
| <a name="input_iac_impersonators"></a> [iac\_impersonators](#input\_iac\_impersonators) | A list of fully-qualified IAM accounts that will be allowed to impersonate the IaC automation service account. If no<br/>accounts are supplied, impersonation will not be setup by the script.<br/>E.g.<br/>impersonators = [<br/>  "group:devsecops@example.com",<br/>  "group:admins@example.com",<br/>  "user:jane@example.com",<br/>  "serviceAccount:ci-cd@project.iam.gserviceaccount.com",<br/>] | `list(string)` | `[]` | no |
| <a name="input_iac_roles"></a> [iac\_roles](#input\_iac\_roles) | An optional set of IAM roles to assign to the IaC automation service account.<br/>Default is an empty set. | `set(string)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | An optional set of key:value string pairs that will be added to Google Cloud resources that accept labels.<br/>Alternative: Set common labels in the `google` provider configuration. | `map(string)` | `{}` | no |
| <a name="input_nginx_jwt"></a> [nginx\_jwt](#input\_nginx\_jwt) | An optional NGINX+ JWT to store in Google Secret Manager, with read-only access granted to AR service account. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ar_sa"></a> [ar\_sa](#output\_ar\_sa) | The fully-qualified email address of the Artifact Registry automation service account. |
| <a name="output_deploy_private_key"></a> [deploy\_private\_key](#output\_deploy\_private\_key) | The private deploy key. |
| <a name="output_deploy_public_key"></a> [deploy\_public\_key](#output\_deploy\_public\_key) | The public deploy key. |
| <a name="output_deploy_sa"></a> [deploy\_sa](#output\_deploy\_sa) | The fully-qualified email address of the Cloud Deploy execution service account, if enabled. |
| <a name="output_github_repo"></a> [github\_repo](#output\_github\_repo) | The full name of the repository. |
| <a name="output_html_url"></a> [html\_url](#output\_html\_url) | The URL to the GitHub repository created for this project. |
| <a name="output_http_clone_url"></a> [http\_clone\_url](#output\_http\_clone\_url) | The repo's clone over HTTPS URL. |
| <a name="output_iac_sa"></a> [iac\_sa](#output\_iac\_sa) | The fully-qualified email address of the IaC automation service account. |
| <a name="output_registries"></a> [registries](#output\_registries) | A map of Artifact Registry resources created by the module. |
| <a name="output_repo_identifiers"></a> [repo\_identifiers](#output\_repo\_identifiers) | A map of Artifact Registry resource types to canonical access identifiers. |
| <a name="output_sops_kms_id"></a> [sops\_kms\_id](#output\_sops\_kms\_id) | The identifier of the KMS encryption/decryption key created by the module for sops usage. |
| <a name="output_ssh_clone_url"></a> [ssh\_clone\_url](#output\_ssh\_clone\_url) | The repo's clone with SSH URL. |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | The GCS bucket that will host automation related state. |
| <a name="output_workload_identity_pool_id"></a> [workload\_identity\_pool\_id](#output\_workload\_identity\_pool\_id) | The fully-qualified identifier of the created Workload Identity pool. |
<!-- END_TF_DOCS -->
<!-- markdownlint-enable MD033 MD034 MD060 -->
