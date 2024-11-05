locals {
  kubeconfig = yamldecode(base64decode(volterra_api_credential.automation.data))
  k8s_name   = format("%s-atlantis", var.name)
}

resource "f5xc_blindfold" "atlantis_config" {
  plaintext = base64encode(yamlencode({
    repo-allowlist    = format("github.com/%s", var.github.repo)
    gh-user           = var.github.user
    gh-token          = var.github.pat
    gh-webhook-secret = random_string.webhook.result
  }))
  policy_document = {
    name      = var.name
    namespace = volterra_virtual_site.automation.namespace
  }
}

provider "kubernetes" {
  host                   = local.kubeconfig.clusters[0].cluster.server
  cluster_ca_certificate = base64decode(local.kubeconfig.clusters[0].cluster.certificate-authority-data)
  client_certificate     = base64decode(local.kubeconfig.users[0].user.client-certificate-data)
  client_key             = base64decode(local.kubeconfig.users[0].user.client-key-data)
}

resource "kubernetes_config_map_v1" "unseal_data" {
  metadata {
    name        = format("%s-sealed", local.k8s_name)
    namespace   = volterra_virtual_k8s.automation.namespace
    annotations = var.annotations
    labels      = var.labels
  }
  data = {
    "secrets.json" = jsonencode({
      "/atlantis/config.yaml" = f5xc_blindfold.atlantis_config.sealed
      "/atlantis/adc.json"    = f5xc_blindfold.adc.sealed
    })
  }
}

resource "kubernetes_stateful_set_v1" "atlantis" {
  metadata {
    name        = local.k8s_name
    namespace   = volterra_virtual_k8s.automation.namespace
    annotations = var.annotations
    labels      = var.labels
  }
  spec {
    service_name = local.k8s_name
    replicas     = 1
    update_strategy {
      type = "RollingUpdate"
      rolling_update {
        partition = 0
      }
    }
    selector {
      match_expressions {
        key      = "app.kubernetes.io/name"
        operator = "In"
        values = [
          local.k8s_name,
        ]
      }
    }
    template {
      metadata {
        labels = merge(var.labels, {
          "app.kubernetes.io/name" = local.k8s_name
        })
      }
      spec {
        security_context {
          run_as_non_root = true
          fs_group        = 1000
        }
        container {
          name  = local.k8s_name
          image = "ghcr.io/memes/terraform-google-f5-demo-bootstrap/xc-atlantis:0.1.0"
          env {
            name  = "UNSEAL_JSON"
            value = "/var/lib/unseal/secrets.json"
          }
          env {
            name  = "GOOGLE_APPLICATION_CREDENTIALS"
            value = "/atlantis/adc.json"
          }
          env {
            name  = "ATLANTIS_CONFIG"
            value = "/atlantis/config.yaml"
          }
          env {
            name  = "ATLANTIS_DATA_DIR"
            value = "/atlantis"
          }
          env {
            name  = "ATLANTIS_PORT"
            value = "4141"
          }
          port {
            name           = "atlantis"
            container_port = 4141
          }
          volume_mount {
            name       = local.k8s_name
            mount_path = "/atlantis"
          }
          volume_mount {
            name       = kubernetes_config_map_v1.unseal_data.metadata[0].name
            mount_path = "/var/lib/unseal"
          }
          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "100m"
            }
          }
          liveness_probe {
            period_seconds = 60
            http_get {
              path   = "/healthz"
              port   = 4141
              scheme = "HTTP"
            }
          }
          readiness_probe {
            period_seconds = 60
            http_get {
              path   = "/healthz"
              port   = 4141
              scheme = "HTTP"
            }
          }
        }
        volume {
          name = kubernetes_config_map_v1.unseal_data.metadata[0].name
          config_map {
            name = kubernetes_config_map_v1.unseal_data.metadata[0].name
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = local.k8s_name
      }
      spec {
        access_modes = [
          "ReadWriteOnce",
        ]
        resources {
          requests = {
            # TODO @memes - modify if larger deployments or deep git history causes a problem
            storage = "5Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "atlantis" {
  metadata {
    name        = local.k8s_name
    namespace   = volterra_virtual_k8s.automation.namespace
    annotations = var.annotations
    labels      = var.labels
  }
  spec {
    type = "ClusterIP"
    port {
      name        = local.k8s_name
      port        = 80
      target_port = 4141
    }
    selector = {
      "app.kubernetes.io/name" = local.k8s_name
    }
  }
}
