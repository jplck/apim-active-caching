terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Placeholder image used only at first provision. azd builds/pushes the real
# middleware/refresher images and updates the apps on `azd deploy`; the
# lifecycle ignore_changes below stops a later `terraform apply` from reverting
# azd's image back to this placeholder.
locals {
  placeholder_image = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"

  # Postgres MI connection contract shared by both workloads. No password: the
  # apps mint an Entra access token for PGUSER using AZURE_CLIENT_ID.
  postgres_env_common = {
    PGHOST     = var.postgres_fqdn
    PGPORT     = tostring(var.postgres_port)
    PGDATABASE = var.postgres_database
    PGSSLMODE  = "require"
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_container_app_environment" "this" {
  name                       = "cae-${var.base}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = var.tags
}

# ---------------------------------------------------------------------------
# Middleware — always-on FastAPI Container App (external ingress). APIM imports
# its OpenAPI and proxies to this URL. Reads Postgres with the middleware
# identity's Entra token (PGUSER = middleware role, no DB password).
# azd-service-name tag tells `azd deploy` which app to push the image to.
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "middleware" {
  name                         = "middleware-${var.token}"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  tags                         = merge(var.tags, { "azd-service-name" = "middleware" })

  identity {
    type         = "UserAssigned"
    identity_ids = [var.middleware_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.middleware_identity_id
  }

  ingress {
    external_enabled = true
    target_port      = var.container_port
    transport        = "auto"
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 1
    max_replicas = 2

    container {
      name   = "middleware"
      image  = local.placeholder_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "PGHOST"
        value = local.postgres_env_common.PGHOST
      }
      env {
        name  = "PGPORT"
        value = local.postgres_env_common.PGPORT
      }
      env {
        name  = "PGDATABASE"
        value = local.postgres_env_common.PGDATABASE
      }
      env {
        name  = "PGSSLMODE"
        value = local.postgres_env_common.PGSSLMODE
      }
      env {
        name  = "PGUSER"
        value = var.middleware_role
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = var.middleware_client_id
      }
      env {
        name  = "PORT"
        value = tostring(var.container_port)
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}

# ---------------------------------------------------------------------------
# Refresher — cron Container Apps Job. Workday ISU credentials arrive as Key
# Vault secret references (resolved by the refresher identity at container
# startup) and are surfaced as WORKDAY_USERNAME / WORKDAY_PASSWORD env vars, so
# the app just reads os.environ — no Key Vault SDK call on the hot path. Writes
# Postgres with the refresher identity's Entra token.
# ---------------------------------------------------------------------------
resource "azurerm_container_app_job" "refresher" {
  name                         = "refresher-${var.token}"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  replica_timeout_in_seconds   = 1800
  replica_retry_limit          = 1
  tags                         = merge(var.tags, { "azd-service-name" = "refresher" })

  identity {
    type         = "UserAssigned"
    identity_ids = [var.refresher_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.refresher_identity_id
  }

  schedule_trigger_config {
    cron_expression          = var.refresh_cron
    parallelism              = 1
    replica_completion_count = 1
  }

  # Key Vault secret references: the platform resolves these to secret values at
  # job start using the refresher identity (which holds Key Vault Secrets User).
  secret {
    name                = "workday-username"
    key_vault_secret_id = var.workday_username_secret_id
    identity            = var.refresher_identity_id
  }
  secret {
    name                = "workday-password"
    key_vault_secret_id = var.workday_password_secret_id
    identity            = var.refresher_identity_id
  }

  template {
    container {
      name   = "refresher"
      image  = local.placeholder_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "WORKDAY_USERNAME"
        secret_name = "workday-username"
      }
      env {
        name        = "WORKDAY_PASSWORD"
        secret_name = "workday-password"
      }
      env {
        name  = "WORKDAY_SOAP_URL"
        value = var.workday_soap_url
      }
      env {
        name  = "WORKDAY_API_VERSION"
        value = var.workday_api_version
      }
      env {
        name  = "SYNC_MODE"
        value = var.sync_mode
      }
      env {
        name  = "WATERMARK_LOOKBACK_SECONDS"
        value = tostring(var.watermark_lookback_seconds)
      }
      env {
        name  = "PAGE_COUNT"
        value = tostring(var.page_count)
      }
      env {
        name  = "EFFECTIVE_FLOOR"
        value = var.effective_floor
      }
      env {
        name  = "EFFECTIVE_LOOKAHEAD_DAYS"
        value = tostring(var.effective_lookahead_days)
      }
      env {
        name  = "PGHOST"
        value = local.postgres_env_common.PGHOST
      }
      env {
        name  = "PGPORT"
        value = local.postgres_env_common.PGPORT
      }
      env {
        name  = "PGDATABASE"
        value = local.postgres_env_common.PGDATABASE
      }
      env {
        name  = "PGSSLMODE"
        value = local.postgres_env_common.PGSSLMODE
      }
      env {
        name  = "PGUSER"
        value = var.refresher_role
      }
      env {
        name  = "AZURE_CLIENT_ID"
        value = var.refresher_client_id
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }
}
