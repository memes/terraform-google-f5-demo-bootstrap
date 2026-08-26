#

![GitHub release](https://img.shields.io/github/v/release/memes/terraform-google-f5-demo-bootstrap?sort=semver)
![GitHub last commit](https://img.shields.io/github/last-commit/memes/terraform-google-f5-demo-bootstrap)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](CODE_OF_CONDUCT.md)

This Terraform module creates an opinionated automation for an F5 on GCP demo.

## GitHub immutable OIDC subject claims and GitHub organizations

As of July 15 2026, all new GitHub repositories use [immutable subject claims](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims)
for OIDC. This changes the format of the OIDC subject set by GitHub, and the Workload Identity assertion used to
validate the OIDC claim. The module can automatically determine the format of the claim if the repo is associated with
a personal GitHub account, but if the repo belongs to a GitHub organization, the module must be informed so it can
validate appropriately.

> NOTE: If you have an existing bootstrapped repo created before July 15, 2026, you will need to opt in to immutable
> claims or GitHub integration with Workload Identity will be broken regardless of repo owner being an individual or
> organization. See the OIDC settings page at https://github.com/OWNER/REPO/settings/actions/oidc-configuration,
> substituting the correct value for OWNER and REPO of the existing bootstrapped repo.

### Recommended pattern for repos owned by an organization

When trying to bootstrapping a new repo, or updating a prior bootstrapped repo, that is hosted in a GitHub organization
use the `github_options.org` field to match the target organization in the `github` provider. This avoids a potential
mismatch where the GitHub provider chooses an individual or organization target based on environment variables, which
the module does not know about.

E.g., to target a repo in `F5DevCentral` organization, in your `main.tf`:

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    ...
  }
}

provider "github" {
  # Explicitly set the target organization used by provider when creating/updating repository.
  owner = "F5DevCentral"
}

module "bootstrap" {
  source            = "registry.terraform.io/memes/f5-demo-bootstrap/google"
  ...
  github_options    = {
    # Ensure that the Workload Identity assertion uses the correct values for the immutable OIDC subject claim
    org = "F5DevCentral"
    ...
  }
  ...
}
```

## Further Github workflow hardening

Additional hardening steps that cannot yet be managed by this module:

* Manually enforce maintainer approval for workflows to limit risk from unauthorized PRs. See *Approval for
  running fork pull request workflows from contributors* section of repo config at
  https://github.com/OWNER/REPO/settings/actions and
  [provider issue 2108](https://github.com/integrations/terraform-provider-github/issues/2108).

<!-- markdownlint-disable MD033 MD034 -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_github"></a> [github](#requirement\_github) | >= 6.12 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 7.31 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | >= 7.31 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.2 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [github_actions_repository_permissions.automation](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_repository_permissions) | resource |
| [github_actions_secret.ar_sa](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_secret.deploy_sa](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_secret.iac_sa](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_secret.provider_id](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_secret) | resource |
| [github_actions_variable.bootstrap_name](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_actions_variable.nginx_jwt](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_actions_variable.project_id](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_actions_variable.registry](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_actions_variable.secrets](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/actions_variable) | resource |
| [github_repository.automation](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository) | resource |
| [github_repository_collaborator.collaborators](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_collaborator) | resource |
| [github_repository_deploy_key.automation](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository_deploy_key) | resource |
| [github_workflow_repository_permissions.automation](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/workflow_repository_permissions) | resource |
| [google-beta_google_project_service_identity.ids](https://registry.terraform.io/providers/hashicorp/google-beta/latest/docs/resources/google_project_service_identity) | resource |
| [google_artifact_registry_repository.automation](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository.oci_virt](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository.upstream_oci_docker_hub](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository.upstream_oci_f5_ai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository.upstream_oci_nginx](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository) | resource |
| [google_artifact_registry_repository_iam_member.ar](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.automation_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.automation_writer](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.iac](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_artifact_registry_repository_iam_member.virtual_reader](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/artifact_registry_repository_iam_member) | resource |
| [google_iam_workload_identity_pool.bots](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool) | resource |
| [google_iam_workload_identity_pool_iam_member.iac](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/iam_workload_identity_pool_iam_member) | resource |
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
| [google_secret_manager_secret.nginx_jwt](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret.secrets](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret.upstream_oci_password_f5_ai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret.upstream_oci_password_nginx](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret) | resource |
| [google_secret_manager_secret_iam_member.upstream_oci_password_f5_ai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |
| [google_secret_manager_secret_iam_member.upstream_oci_password_nginx](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_iam_member) | resource |
| [google_secret_manager_secret_version.nginx_jwt](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_secret_manager_secret_version.secrets](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_secret_manager_secret_version.upstream_oci_password_f5_ai](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
| [google_secret_manager_secret_version.upstream_oci_password_nginx](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/secret_manager_secret_version) | resource |
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
| [github_organization.default](https://registry.terraform.io/providers/integrations/github/latest/docs/data-sources/organization) | data source |
| [github_user.default](https://registry.terraform.io/providers/integrations/github/latest/docs/data-sources/user) | data source |
| [google_storage_project_service_account.default](https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/storage_project_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | The common name (and prefix) to use for Google Cloud and GitHub resources (see also `github_options`). | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The Google Cloud project that will host resources. | `string` | n/a | yes |
| <a name="input_bootstrap_apis"></a> [bootstrap\_apis](#input\_bootstrap\_apis) | An optional set of Google Cloud APIs to enable during bootstrap, in addition<br/>to those required for bootstrap resources. Default is an empty set. | `set(string)` | `[]` | no |
| <a name="input_cloud_deploy_roles"></a> [cloud\_deploy\_roles](#input\_cloud\_deploy\_roles) | An optional set of IAM roles to assign to the Cloud Deploy automation service account, if it is created. Default is an<br/>empty set.<br/>E.g. to support deploying to GKE:<br/>cloud\_deploy\_roles = [<br/>  "roles/container.developer",<br/>] | `set(string)` | `[]` | no |
| <a name="input_f5_ai_repo_credentials"></a> [f5\_ai\_repo\_credentials](#input\_f5\_ai\_repo\_credentials) | An optional username and password pair for the upstream F5 AI container repository. If provided, a remote Artifact<br/>Registry will be created to reference the upstream F5 AI private repository for transparent access to the<br/>private images, along with a Secret Manager secret to contain the password. | <pre>object({<br/>    username = string<br/>    password = string<br/>  })</pre> | `null` | no |
| <a name="input_gcp_options"></a> [gcp\_options](#input\_gcp\_options) | Defines the parameters for the supporting Google Cloud resources that may not be essential to the demo. By default<br/>service accounts and resources to support Infrastructure Manager (managed Terraform IaC) and Cloud Deploy (managed GKE<br/>and Cloud Run deployments) are created, along with a US Cloud Storage bucket to contain the Terraform state. An<br/>Artifact Repository will be created for OCI containers, but not DEB or RPM repos. Use this variable to override one or<br/>more of these defaults as needed. If the flag for virtual OCI repository is set, the local OCI registry, docker hub,<br/>and one or both of NGINX private repository and F5 AI private repository will be added to the virtual server, with<br/>highest priority assigned in that order. | <pre>object({<br/>    enable_infra_manager        = optional(bool, true)<br/>    enable_cloud_deploy         = optional(bool, true)<br/>    services_disable_on_destroy = optional(bool, false)<br/>    disable_dependent_services  = optional(bool, false)<br/>    create_state_bucket         = optional(bool, true)<br/>    ar = optional(object({<br/>      location    = optional(string, "us")<br/>      oci         = optional(bool, true)<br/>      deb         = optional(bool, false)<br/>      rpm         = optional(bool, false)<br/>      docker_hub  = optional(bool, false)<br/>      virtual_oci = optional(bool, false)<br/>    }))<br/>    kms = optional(bool, false)<br/>  })</pre> | <pre>{<br/>  "ar": {<br/>    "deb": false,<br/>    "docker_hub": false,<br/>    "location": "us",<br/>    "oci": true,<br/>    "rpm": false,<br/>    "virtual_oci": false<br/>  },<br/>  "create_state_bucket": true,<br/>  "disable_dependent_services": false,<br/>  "enable_cloud_deploy": true,<br/>  "enable_infra_manager": true,<br/>  "kms": false,<br/>  "services_disable_on_destroy": false<br/>}</pre> | no |
| <a name="input_github_options"></a> [github\_options](#input\_github\_options) | Defines the parameters for the GitHub repository to create for the demo. By default the GitHub repo will be public,<br/>named from the `name` variable and populated from `memes/terraform-google-f5-demo-bootstrap-template` repo. Use this<br/>variable to override one or more of these defaults as needed. | <pre>object({<br/>    private_repo       = optional(bool, false)<br/>    name               = optional(string)<br/>    description        = optional(string, "Bootstrapped automation repository")<br/>    template           = optional(string, "memes/terraform-google-f5-demo-bootstrap-template")<br/>    archive_on_destroy = optional(bool, true)<br/>    collaborators      = optional(set(string))<br/>    ssh_deploy_key     = optional(bool, false)<br/>    org                = optional(string)<br/>  })</pre> | <pre>{<br/>  "archive_on_destroy": true,<br/>  "collaborators": [],<br/>  "description": "Bootstrapped automation repository",<br/>  "name": "",<br/>  "org": null,<br/>  "private_repo": false,<br/>  "ssh_deploy_key": false,<br/>  "template": "memes/terraform-google-f5-demo-bootstrap-template"<br/>}</pre> | no |
| <a name="input_iac_impersonators"></a> [iac\_impersonators](#input\_iac\_impersonators) | A list of fully-qualified IAM accounts that will be allowed to impersonate the IaC automation service account. If no<br/>accounts are supplied, impersonation will not be setup by the script.<br/>E.g.<br/>impersonators = [<br/>  "group:devsecops@example.com",<br/>  "group:admins@example.com",<br/>  "user:jane@example.com",<br/>  "serviceAccount:ci-cd@project.iam.gserviceaccount.com",<br/>] | `list(string)` | `[]` | no |
| <a name="input_iac_options"></a> [iac\_options](#input\_iac\_options) | An optional set of flags to apply to the IaC account. | <pre>object({<br/>    enable_workload_identity_pool_admin = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_iac_roles"></a> [iac\_roles](#input\_iac\_roles) | An optional set of IAM roles to assign to the IaC automation service account.<br/>Default is an empty set. | `set(string)` | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | An optional set of key:value string pairs that will be added to Google Cloud resources that accept labels.<br/>Alternative: Set common labels in the `google` provider configuration. | `map(string)` | `{}` | no |
| <a name="input_nginx_jwt"></a> [nginx\_jwt](#input\_nginx\_jwt) | An optional NGINX+ JWT to store in Google Secret Manager. If provided, a remote Artifact Registry will be created to<br/>reference the upstream NGINX private Docker repository for transparent access to the private images.<br/>NOTE: Principal access to the secret will not be established by this module; module consumers will be required to<br/>assign the appropriate IAM roles to read or modify the secret as needed. | `string` | `null` | no |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | An optional map of Secret names to values (strings-only) that will be created. A Secret Manager secret will be created<br/>for each key in the map, and a GitHub actions variable of the form `{KEY_NAME}_SECRET` containing the Secret Manager<br/>identity. The value must be a string; use `jsonencode` or similar to include structured or binary data.<br/>NOTE: Values are allowed to be null/empty.<br/>NOTE 2: The input variables `nginx_jwt` and `f5_ai_repo_credentials` are preferred for those secrets, as they will<br/>trigger creation of Artifact Registries. Avoid using the same value in both places, but use `secrets` input if you<br/>want to store either of those without triggering creation of supporting resources. | `map(string)` | `null` | no |
| <a name="input_state_bucket_options"></a> [state\_bucket\_options](#input\_state\_bucket\_options) | Defines the parameters for the IaC GCS state bucket, if enabled in gcp\_options. | <pre>object({<br/>    class          = optional(string, "STANDARD")<br/>    location       = optional(string, "US")<br/>    force_destroy  = optional(bool, true)<br/>    uniform_access = optional(bool, true)<br/>    versioning     = optional(bool, true)<br/>  })</pre> | <pre>{<br/>  "class": "STANDARD",<br/>  "force_destroy": true,<br/>  "location": "US",<br/>  "uniform_access": true,<br/>  "versioning": true<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ar_sa"></a> [ar\_sa](#output\_ar\_sa) | The fully-qualified email address of the Artifact Registry automation service account, if created. |
| <a name="output_bootstrap_name"></a> [bootstrap\_name](#output\_bootstrap\_name) | The name used when bootstrapping resources. |
| <a name="output_deploy_private_key"></a> [deploy\_private\_key](#output\_deploy\_private\_key) | The private deploy key, if created. |
| <a name="output_deploy_public_key"></a> [deploy\_public\_key](#output\_deploy\_public\_key) | The public deploy key, if created. |
| <a name="output_deploy_sa"></a> [deploy\_sa](#output\_deploy\_sa) | The fully-qualified email address of the Cloud Deploy execution service account, if enabled. |
| <a name="output_github_repo"></a> [github\_repo](#output\_github\_repo) | The full name of the repository. |
| <a name="output_html_url"></a> [html\_url](#output\_html\_url) | The URL to the GitHub repository created for this project. |
| <a name="output_http_clone_url"></a> [http\_clone\_url](#output\_http\_clone\_url) | The repo's clone over HTTPS URL. |
| <a name="output_iac_sa"></a> [iac\_sa](#output\_iac\_sa) | The fully-qualified email address of the IaC automation service account. |
| <a name="output_nginx_jwt"></a> [nginx\_jwt](#output\_nginx\_jwt) | If an NGINX JWT secret was created during bootstrap, return the fully-qualified and local identifiers, if appropriate. |
| <a name="output_registries"></a> [registries](#output\_registries) | A map of Artifact Registry resources created by the module. |
| <a name="output_repo_identifiers"></a> [repo\_identifiers](#output\_repo\_identifiers) | A map of Artifact Registry resource types to canonical access identifiers. |
| <a name="output_secrets"></a> [secrets](#output\_secrets) | If an F5 AI license secret was created during bootstrap, return the fully-qualified and local identifiers, if appropriate. |
| <a name="output_sops_kms_id"></a> [sops\_kms\_id](#output\_sops\_kms\_id) | The identifier of the KMS encryption/decryption key created by the module for sops usage, if KMS enabled. |
| <a name="output_ssh_clone_url"></a> [ssh\_clone\_url](#output\_ssh\_clone\_url) | The repo's clone with SSH URL. |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | The GCS bucket that will host automation related state, if created. |
| <a name="output_workload_identity_pool_id"></a> [workload\_identity\_pool\_id](#output\_workload\_identity\_pool\_id) | The fully-qualified identifier of the created Workload Identity pool. |
<!-- END_TF_DOCS -->
<!-- markdownlint-enable MD033 MD034 -->
