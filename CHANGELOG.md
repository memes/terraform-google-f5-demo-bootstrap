# Changelog

## [0.7.0](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.6.1...v0.7.0) (2026-09-30)


### ⚠ BREAKING CHANGES

* This removes modules and containers from the repo.
* GitHub actions in existing repos in a GitHub organization will break unless the `github_options.org` field and `github` provider are updated to acknowledge the org correctly.

### Features

* Add Docker Hub repo option and verify creds ([07d657d](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/07d657d22b252f08660eff62ea2a6da78e1ccc41))
* Add generic secrets, remove f5_ai_license ([5f8dad9](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/5f8dad99c7f611fdfe8116915796fed253aac145))
* Remove support for Atlantis on F5 XC RE ([22a470e](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/22a470e7d8963e34935de6899fe7bd124971fae7))
* Virtual OCI repo with private upstreams ([376bffc](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/376bffc6b0894e7e7f632a463d29f1e45d0332ca))


### Bug Fixes

* Add TF dependency on secret IAM for AR ([37d52d9](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/37d52d9afbadbabc17aadc89268b58ccece01e47))
* Allow AR identity to read F5 AI password ([5b5381d](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/5b5381d8660fe01c2dff32dbc7c53f953b147f41))
* AR service identity can read harbor password ([a1b38ea](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/a1b38ea58de93f881aa808a187e44b3182316e63))
* AR svc dentity reader role to repos for virt ([6e026eb](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/6e026eb265d731e8fd5c416fc9235cb169cad43e))
* Cherry picked fixes from cloud_deploy branch ([a6d8868](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/a6d88682911878a3ab192e11e19a797fe03ffbbb))
* Consistent resource naming, virt OCI optional ([070d2b7](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/070d2b7017dcb9bf8d945564c5c0b5e3da975f33))
* Default to f5-architects bootstrap template ([3f4ccf6](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/3f4ccf609312215248818226570ff2fd01a11dc4))
* Do not enable immutable tags on OCI repo ([0cddb17](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/0cddb17358a189c55d0e9e4d92de28b47fb69c02))
* Improve GitHub actions security ([af1da85](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/af1da855bf2c00278599ddc9c63fd1e59593b08e))
* Include bootstrap name as GHA variable ([8b89f8e](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/8b89f8e913dfbb29037dd622e3905ec30d828510))
* Make virtual repo an option, clean up logic ([6e42041](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/6e42041dc0aed2ee105777ec7f7ee9824115f99f))
* Support additional AR repos in virt OCI repo ([35a72d3](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/35a72d30a4595f9b79731c75420e58eef9c979d9))
* Use correct F5 AI password secret ([0f24d1b](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/0f24d1b56c9a85eeb4e171b0c045e97f66a79432))

## [0.6.1](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.6.0...v0.6.1) (2026-07-13)


### Bug Fixes

* Create AR service account only when needed ([33c89cc](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/33c89ccc17ec0964782376c45f1d806a9e2db4c6))
* Make IaC bucket creation optional. ([33c89cc](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/33c89ccc17ec0964782376c45f1d806a9e2db4c6))
* Make SSH deploy key optional ([33c89cc](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/33c89ccc17ec0964782376c45f1d806a9e2db4c6))

## [0.6.0](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.5.1...v0.6.0) (2026-04-15)


### Features

* Add IaC service account flags ([035a2a5](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/035a2a55933f6fdd4b4e464932a59cdc3eebb0a9))


### Bug Fixes

* Bump Google provider to latest ([422a667](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/422a66716f548ee87c96592ed7078a2cbb85dfc3))

## [0.5.1](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.5.0...v0.5.1) (2026-03-05)


### Bug Fixes

* IaC sa gets config.agent if Infra Manager set ([1e3ef62](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/1e3ef629b2c4563fa1745a308adb770eadc1a90a))

## [0.5.0](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.4.2...v0.5.0) (2026-03-05)


### Features

* Optional project roles for Cloud Deploy sa ([df1fb4e](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/df1fb4e3c9e5cb0eaa7887f87fb34ea9c88dd88d))


### Bug Fixes

* Only enable Secret Manager/KMS APIs on demand ([f76df8e](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/f76df8ecda30bbe562bedb1f0ee64f68d4f22724))
* Typo in bootstrap_apis ([0dbe623](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/0dbe6230f380325b603b2b5416f580c7367595ba))
* Was mixing lists and sets for deploy roles ([2797b2d](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/2797b2d5eaa0e1aca277687941b862e0a87cbdde))

## [0.4.2](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.4.1...v0.4.2) (2026-01-28)


### Bug Fixes

* Add Secret Manager output for NGINX JWT ([b2db4e2](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/b2db4e208d97b19147cc77dbdae87b1fc268cef2))
* Add Secret Manager output for NGINX JWT ([6902573](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/690257313076e8f7a35418bd5c11e470f8b1b66c))

## [0.4.1](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.4.0...v0.4.1) (2026-01-27)


### Bug Fixes

* Default to upstream repo template ([44e4316](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/44e4316e143919b158e31894ee9e00cd0be71a6e))
* Default to upstream repo template ([758a4b2](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/758a4b212dcd641aff07d85e54eb777641e8402e))

## [0.4.0](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.3.3...v0.4.0) (2026-01-27)


### Bug Fixes

* Move collaborators to github_options ([811a41b](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/811a41ba95ea42b4ad1a82b1adb52761ef6c52cb))
* private_repo should be optional ([0d01762](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/0d017620be23f3bccb980de4a37ccc109c08adb5))
* SOPS KMS key id is optional ([8953992](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/8953992bb8bcc3e187845cd4998eb6f0fef226bc))


### Continuous Integration

* Fix release version as 0.4.0 ([b637bd0](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/b637bd063f6ec19307620d4bec0ae3ab2911b685))

## [0.3.3](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.3.2...v0.3.3) (2025-09-17)


### Bug Fixes

* Disable building of XC Atlantis container ([c417a7d](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/c417a7de8efceba6ffecb13bb6ac051f7f7c3408))
* Disable building of XC Atlantis container ([33415b8](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/33415b82f7a35c81b2106fc9097c72dcdeaee59a))
* Prefer to archive GitHub repo over destroy ([875f361](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/875f36159de54318316178806447b736ece04d07))
* Prefer to archive GitHub repo over destroy ([d7b6e26](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/d7b6e26aab0f6d0527c5823789cee415398a464c))

## [0.3.2](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.3.1...v0.3.2) (2025-09-15)


### Bug Fixes

* Workload Identity Pool display name &lt;= 32char ([d3f7479](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/d3f74794f40a888e9513218a9150f1912a7de08a))
* Workload Identity Pool display name &lt;= 32char ([af8004d](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/af8004d35e79c00977121c0a0a697af5f1e1d882))

## [0.3.1](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.3.0...v0.3.1) (2025-09-15)


### Bug Fixes

* Resolve error when repo template is provided ([1ed8398](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/1ed839872714c3e96076db68fb907cdebedb0918))
* Resolve error when repo template is provided ([b02fc62](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/b02fc62fee5de56e9d36ff496209af6a3679b802))

## [0.3.0](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.2.0...v0.3.0) (2025-09-15)


### Features

* Cloud Deploy module ([2e458d9](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/2e458d945b5fd9a2ae2eaa7b5c0d762a14cae0a5))
* Make Infra Manager and Cloud Deploy optional ([884e72a](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/884e72a15e3f8ddfee4c7f212bf4e49b0d711218))


### Bug Fixes

* Add a GitHub variable with the project id ([cdd61dd](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/cdd61dd481c3753e9e544cd13bcd09564268996e))
* Add AR SA email as GitHub secret ([29f7aca](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/29f7acab7993134b2df7137014d11e79fc940694))
* Add labels and options to cloud-deploy vars ([1216fc9](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/1216fc976baba6be05c1a1089b11f13ffc37eb09))
* Add prevent_destroy flag to GitHub collabs ([d97fbed](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/d97fbedeb28603d8910da184a2ee332ee6992498))
* Add service account for AR and bind to GitHub ([c71992f](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/c71992fa036d4bdbcf738bcf932c1ce6c309042f))
* Add support for NGINX+ JWT as GCP secret ([1dda6d3](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/1dda6d3978e232ca043e96422bd18da1d248cb87))
* Allow select OIDC accounts to act as IaC ([20a0df2](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/20a0df22830db726ae86c19bd7133a528c96f77f))
* Correct references for optional deploy SA ([1edc2b2](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/1edc2b23ce3f9a2eda18e3c8d4aa24c8a08720e2))
* Declare google-beta ([9db3958](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/9db3958535ebccd49ef530fbe5ec9b36f00c1ae6))
* Don't delete repo on destroy, split options ([dad443d](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/dad443d6bf82efac5480852a9cd3bbe349e58282))
* Fix role name for Cloud Deploy releaser ([0d2705f](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/0d2705fe5a685f4f3d6c7b7b59d18cbb3d9b1850))
* Fixed messed up references, use google-beta ([d00a78f](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/d00a78f756bff579eda6bf73e58d95104c20cff8))
* IaC SA should be an admin of the AR repos. ([9494f1a](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/9494f1af615fdce22a8d51fbf4805aa264546284))
* Incorrect roles for deploy SA on bucket ([10ee9e3](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/10ee9e38348f264af416da7d704e9a1c68a0d56a))
* Project ID variable ([b9370b1](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/b9370b1830cef7e78d47ef9634509be0ea415bbb))
* Remove duplicate resources in root module ([00f9dbe](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/00f9dbe7a3bdd9be26aaf63a1ad7669f79a9a858))
* Remove infrastructure-manager module ([05821ff](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/05821ff7461f234cc24e6433f8cfc823f8165d50))
* Restore IaC SA email GitHub secret ([f5cc02a](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/f5cc02a7c467bbd32d70f4c44ab07a91b841a28c))
* Typo in AR service account accessor ([a0404fd](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/a0404fd8b7ee4ca722f3feac946ca0664e8f8fc5))
* Validation for iac_impersonators ([b2f1966](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/b2f1966f05c81ef73d49e9e1c596cdd1ec3f72f1))

## [0.2.0](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.1.0...v0.2.0) (2025-02-08)


### Features

* Add terraform from private bootstrap repo ([ebfbf4e](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/ebfbf4e3ed8b57188cc818e3b3255769d67c4b80))
* Allow override of GitHub repo name ([329adf7](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/329adf791325fd76a286f9ab39973f3acb803bc0))


### Bug Fixes

* GitHub/Workload Identity broken by condition ([d9f09fc](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/d9f09fcdf0e0dc83d93940052addd23fb9e83111))
* Install OpenTofu; parameterize versions ([9fefcb6](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/9fefcb6cebdc4f63d0200e55442bb86fc6a01049))
* Was using the wrong var for tflint version ([65a76f3](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/65a76f3f6256f2d0bb96019491b1843a691d45b0))

## [0.1.0](https://github.com/memes/terraform-google-f5-demo-bootstrap/compare/v0.0.1...v0.1.0) (2024-11-04)


### Features

* Atlantis container modified for XC REs ([378247a](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/378247a74a5d1fc3460458c675edfc31e2e8e728))


### Bug Fixes

* Update Atlantis and supporting tool versions ([9ea24b0](https://github.com/memes/terraform-google-f5-demo-bootstrap/commit/9ea24b03c42dabdf7cdcc3eb45187a443b1b2ef9))
