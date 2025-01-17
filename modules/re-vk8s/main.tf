terraform {
  required_version = ">= 1.5"
  required_providers {
    f5xc = {
      source  = "registry.terraform.io/memes/f5xc"
      version = ">= 0.1"
    }
    github = {
      source  = "integrations/github"
      version = ">= 6.3"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 6.9"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.33"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
    volterra = {
      source  = "volterraedge/volterra"
      version = ">= 0.11.39"
    }
  }
}

resource "google_service_account" "automation" {
  project      = var.project_id
  account_id   = format("%s-vk8s", var.name)
  display_name = "vk8s mapped identity"
  description  = "F5 XC vk8s mapped identity"
}

# TODO @memes - Revist if and when XC vk8s has a published OIDC discovery doc; e.g. .well-known/openid-configuration
# can be used to interact via workload identity. For now, a JSON key must be used since a token will be too short lived.
resource "google_service_account_key" "automation" {
  service_account_id = google_service_account.automation.name
  private_key_type   = "TYPE_GOOGLE_CREDENTIALS_FILE"
}

resource "volterra_virtual_site" "automation" {
  name        = var.name
  namespace   = var.namespace
  description = var.description
  labels      = var.labels
  annotations = var.annotations
  site_type   = "REGIONAL_EDGE"
  site_selector {
    expressions = [
      format("ves.io/region == %s", var.region)
    ]
  }
}

resource "volterra_virtual_k8s" "automation" {
  name        = var.name
  namespace   = var.namespace
  description = var.description
  labels      = var.labels
  annotations = var.annotations
  vsite_refs {
    name      = volterra_virtual_site.automation.name
    namespace = volterra_virtual_site.automation.namespace
  }
}

resource "volterra_api_credential" "automation" {
  name                  = substr(volterra_virtual_k8s.automation.name, 0, 31)
  api_credential_type   = "KUBE_CONFIG"
  virtual_k8s_name      = volterra_virtual_k8s.automation.name
  virtual_k8s_namespace = volterra_virtual_k8s.automation.namespace
  expiry_days           = var.expiration_days
}

resource "volterra_secret_policy" "automation" {
  name        = var.name
  namespace   = volterra_virtual_site.automation.namespace
  description = var.description
  labels      = var.labels
  annotations = var.annotations
  allow_f5xc  = false
  rule_list {
    rules {
      metadata {
        name        = format("%s-allow", var.name)
        description = "Allow matching clients to access secret"
      }
      spec {
        action = "ALLOW"
        # TODO @memes - figure out the correct expression to limit access from wingman in vk8s deployment.
        client_name_matcher {
          regex_values = [
            ".*"
          ]
        }
        # client_selector {
        #   expressions = [
        #     join(",", [for k,v in var.labels: format("%s==%s", k, v)]),
        #   ]
        # }
      }
    }
    rules {
      metadata {
        name        = format("%s-deny", var.name)
        description = "Default deny access to secret"
      }
      spec {
        action = "DENY"
        client_name_matcher {
          regex_values = [
            ".*"
          ]
        }
      }
    }
  }
}

resource "volterra_origin_pool" "atlantis" {
  name                   = format("%s-atlantis", var.name)
  namespace              = volterra_virtual_k8s.automation.namespace
  description            = var.description
  labels                 = var.labels
  annotations            = var.annotations
  endpoint_selection     = "LOCAL_PREFERRED"
  loadbalancer_algorithm = "LB_OVERRIDE"
  origin_servers {
    k8s_service {
      service_name = format("%s-atlantis.%s", var.name, volterra_virtual_k8s.automation.namespace)
      site_locator {
        virtual_site {
          name      = volterra_virtual_site.automation.name
          namespace = volterra_virtual_site.automation.namespace
        }
      }
      vk8s_networks = true
    }
  }
  port   = 80
  no_tls = true
}

resource "volterra_service_policy" "atlantis" {
  name        = format("%s-atlantis", var.name)
  namespace   = volterra_virtual_k8s.automation.namespace
  description = var.description
  labels      = var.labels
  annotations = var.annotations
  algo        = "FIRST_MATCH"
  rule_list {
    rules {
      metadata {
        name        = format("%s-atlantis-allow-webhook", var.name)
        description = "Permit Webhook event handling"
      }
      spec {
        action = "ALLOW"
        headers {
          name = "Content-Type"
          item {
            regex_values = [
              "application/json",
              "application/x-www-form-urlencoded",
            ]
          }
        }
        http_method {
          methods = [
            "POST",
          ]
        }
        path {
          prefix_values = [
            "/events",
          ]
        }
        waf_action {
          none = true
        }
      }
    }
    rules {
      metadata {
        name        = format("%s-atlantis-deny-all", var.name)
        description = "Deny all other requests"
      }
      spec {
        action     = "DENY"
        any_client = true
        waf_action {
          none = true
        }
      }
    }
  }
}

resource "volterra_http_loadbalancer" "atlantis" {
  name                            = var.name
  namespace                       = volterra_virtual_k8s.automation.namespace
  description                     = var.description
  labels                          = var.labels
  annotations                     = var.annotations
  advertise_on_public_default_vip = true
  disable_api_definition          = true
  disable_api_discovery           = true
  disable_bot_defense             = true
  no_challenge                    = true
  disable_client_side_defense     = true
  l7_ddos_action_default          = true
  default_route_pools {
    pool {
      name      = volterra_origin_pool.atlantis.name
      namespace = volterra_origin_pool.atlantis.namespace
    }
  }
  domains = [
    var.domain,
  ]
  source_ip_stickiness  = true
  disable_ip_reputation = true
  https_auto_cert {
    http_redirect = true
    add_hsts      = true
  }
  disable_malicious_user_detection = true
  disable_rate_limit               = true
  active_service_policies {
    policies {
      name      = volterra_service_policy.atlantis.name
      namespace = volterra_service_policy.atlantis.namespace
    }
  }
  service_policies_from_namespace = true
  disable_trust_client_ip_headers = true
  user_id_client_ip               = true
  disable_waf                     = true
}

# Generate a random token to validate incoming webhook requests from GitHub
resource "random_string" "webhook" {
  length = 32
}

resource "github_repository_webhook" "atlantis" {
  repository = split("/", var.github.repo)[1]
  active     = true
  configuration {
    url          = format("https://%s/events", var.domain)
    content_type = "application/json"
    insecure_ssl = false
    secret       = random_string.webhook.result
  }

  events = [
    "issue_comment",
    "pull_request",
    "pull_request_review",
    "pull_request_review_comment",
  ]
}

resource "f5xc_blindfold" "adc" {
  plaintext = google_service_account_key.automation.private_key
  policy_document = {
    name      = var.name
    namespace = volterra_virtual_site.automation.namespace
  }
  depends_on = [
    google_service_account_key.automation,
    volterra_secret_policy.automation,
  ]
}
