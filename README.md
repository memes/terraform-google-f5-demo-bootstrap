# f5-google-demo-bootstrap

![GitHub release](https://img.shields.io/github/v/release/memes/f5-google-demo-bootstrap?sort=semver)
![Maintenance](https://img.shields.io/maintenance/yes/2024)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)

<!-- markdownlint-disable MD033 MD034-->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_github"></a> [github](#requirement\_github) | >= 6.3 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.9 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [github_actions_secret.automation_sa](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_secret.provider_id](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_variable.registry](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_repository.automation](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository) | resource |
| [github_repository_collaborator.collaborators](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_collaborator) | resource |
| [github_repository_deploy_key.automation](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_deploy_key) | resource |
| [google_artifact_registry_repository.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository_iam_member.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_iam_workload_identity_pool.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_provider.github](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_provider) | resource |
| [google_kms_crypto_key.gcs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key) | resource |
| [google_kms_crypto_key.sops](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key) | resource |
| [google_kms_crypto_key_iam_member.gcs](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_crypto_key_iam_member) | resource |
| [google_kms_key_ring.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_key_ring) | resource |
| [google_kms_key_ring_iam_member.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/kms_key_ring_iam_member) | resource |
| [google_project_iam_member.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_member) | resource |
| [google_project_service.apis](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_service) | resource |
| [google_service_account.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |
| [google_service_account_iam_member.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_service_account_iam_member.impersonation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account_iam_member) | resource |
| [google_storage_bucket.state](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket) | resource |
| [google_storage_bucket_iam_member.admin](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket_iam_member) | resource |
| [tls_private_key.automation](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [google_project.project](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/project) | data source |
| [google_storage_project_service_account.default](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | The common name to use for resources. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | n/a | `string` | n/a | yes |
| <a name="input_automation_roles"></a> [automation\_roles](#input\_automation\_roles) | An optional set of IAM roles to assign to the automation service account.<br/>Default is an empty set. | `set(string)` | `[]` | no |
| <a name="input_bootstrap_apis"></a> [bootstrap\_apis](#input\_bootstrap\_apis) | An optional set of Google Cloud APIs to enable during bootstrap, in addition<br/>to those required for bootstrap resources. Default is an empty set. | `set(string)` | `[]` | no |
| <a name="input_collaborators"></a> [collaborators](#input\_collaborators) | An optional set of GitHub users that will be invited to collaborate on the created repo. | `set(string)` | `[]` | no |
| <a name="input_impersonators"></a> [impersonators](#input\_impersonators) | A list of fully-qualified IAM accounts that will be allowed to impersonate the automation service account. If no<br/>accounts are supplied, impersonation will not be setup by the script.<br/>E.g.<br/>impersonators = [<br/>  "group:devsecops@example.com",<br/>  "group:admins@example.com",<br/>  "user:jane@example.com",<br/>  "serviceAccount:ci-cd@project.iam.gserviceaccount.com",<br/>] | `list(string)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | An optional set of key:value string pairs that will be added to GCP resources<br/>that accept labels. | `map(string)` | `{}` | no |
| <a name="input_options"></a> [options](#input\_options) | n/a | <pre>object({<br/>    services_disable_on_destroy = bool<br/>    disable_dependent_services  = bool<br/>    bucket_class                = string<br/>    bucket_location             = string<br/>    bucket_force_destroy        = bool<br/>    bucket_uniform_access       = bool<br/>    bucket_versioning           = bool<br/>    private_repo                = bool<br/>    ar = object({<br/>      location = string<br/>      oci      = bool<br/>      deb      = bool<br/>      rpm      = bool<br/>    })<br/>    repo_description = string<br/>  })</pre> | <pre>{<br/>  "ar": {<br/>    "deb": false,<br/>    "location": "us",<br/>    "oci": true,<br/>    "rpm": false<br/>  },<br/>  "bucket_class": "STANDARD",<br/>  "bucket_force_destroy": true,<br/>  "bucket_location": "US",<br/>  "bucket_uniform_access": true,<br/>  "bucket_versioning": true,<br/>  "disable_dependent_services": false,<br/>  "private_repo": false,<br/>  "repo_description": "Bootstrapped automation repository",<br/>  "services_disable_on_destroy": false<br/>}</pre> | no |
| <a name="input_template_repo"></a> [template\_repo](#input\_template\_repo) | n/a | <pre>object({<br/>    owner = string<br/>    repo  = string<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_deploy_privkey"></a> [deploy\_privkey](#output\_deploy\_privkey) | The private deploy key. |
| <a name="output_deploy_pubkey"></a> [deploy\_pubkey](#output\_deploy\_pubkey) | The public deploy key. |
| <a name="output_github_repo"></a> [github\_repo](#output\_github\_repo) | The full name of the repository. |
| <a name="output_html_url"></a> [html\_url](#output\_html\_url) | The URL to the GitHub repository created for this project. |
| <a name="output_http_clone_url"></a> [http\_clone\_url](#output\_http\_clone\_url) | The repo's clone over HTTPS URL. |
| <a name="output_registries"></a> [registries](#output\_registries) | A map of Artifact Registry resources created by the module. |
| <a name="output_repo_identifiers"></a> [repo\_identifiers](#output\_repo\_identifiers) | A map of Artifact Registry resource types to canonical access identifiers. |
| <a name="output_sa"></a> [sa](#output\_sa) | The fully-qualified email address of the automation service account. |
| <a name="output_sops_kms_id"></a> [sops\_kms\_id](#output\_sops\_kms\_id) | The identifier of the KMS encryption/decryption key created by the module for sops usage. |
| <a name="output_ssh_clone_url"></a> [ssh\_clone\_url](#output\_ssh\_clone\_url) | The repo's clone with SSH URL. |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | The GCS bucket that will host automation related state. |
| <a name="output_workload_identity_pool_id"></a> [workload\_identity\_pool\_id](#output\_workload\_identity\_pool\_id) | The fully-qualified identifier of the created Workload Identity pool. |
<!-- END_TF_DOCS -->
<!-- markdownlint-enable MD033 MD034 -->
