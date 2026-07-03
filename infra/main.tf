resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

# Shared secret the refresher presents (X-Refresh-Token) to trigger a cache load.
resource "random_password" "refresh_token" {
  length  = 32
  special = false
}

locals {
  token = lower(random_string.suffix.result)
  base  = "${var.environment_name}-${local.token}"
  tags  = { "azd-env-name" = var.environment_name }
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.environment_name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Azure Managed Redis (external cache for APIM)
# ponytail: classic Azure Cache for Redis is retired for new creates, so this
# uses Azure Managed Redis on the cheapest Balanced_B0 SKU. EnterpriseCluster
# policy exposes a single, non-clustered endpoint that APIM's StackExchange.Redis
# client connects to with a plain connection string (no cluster redirects).
# access_keys_authentication_enabled = true so the connection string can use a key.
# ---------------------------------------------------------------------------
resource "azurerm_managed_redis" "this" {
  name                      = "redis-${local.base}"
  location                  = azurerm_resource_group.this.location
  resource_group_name       = azurerm_resource_group.this.name
  sku_name                  = var.redis_sku
  high_availability_enabled = false
  tags                      = local.tags

  default_database {
    clustering_policy                  = "EnterpriseCluster"
    client_protocol                    = "Encrypted"
    access_keys_authentication_enabled = true
  }
}

# ---------------------------------------------------------------------------
# API Management (Standard v2)
# ---------------------------------------------------------------------------
resource "azurerm_api_management" "this" {
  name                = "apim-${local.base}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku
  tags                = local.tags
}

# Wire Azure Managed Redis as APIM's external cache. cache_location "default" =
# usable from any region. Port 10000 + ssl=True is the Managed Redis endpoint.
resource "azurerm_api_management_redis_cache" "this" {
  name              = "default"
  api_management_id = azurerm_api_management.this.id
  connection_string = "${azurerm_managed_redis.this.hostname}:${azurerm_managed_redis.this.default_database[0].port},password=${azurerm_managed_redis.this.default_database[0].primary_access_key},ssl=True,abortConnect=False"
  cache_location    = "default"
}

# Named values shared by the policies (single source of truth via TF vars).
resource "azurerm_api_management_named_value" "cache_key" {
  name                = "CacheKey"
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  display_name        = "CacheKey"
  value               = var.cache_key
}

resource "azurerm_api_management_named_value" "cache_ttl" {
  name                = "CacheTtlSeconds"
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  display_name        = "CacheTtlSeconds"
  value               = tostring(var.cache_ttl_seconds)
}

# The (mocked) Workday backend the refresh branch pulls a full load from. Points at
# the in-APIM mock; swap for a real Workday workers URL to go live.
resource "azurerm_api_management_named_value" "workday_backend_url" {
  name                = "WorkdayBackendUrl"
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  display_name        = "WorkdayBackendUrl"
  value               = "${azurerm_api_management.this.gateway_url}/workday-mock/workers"
}

# Secret that gates the refresh branch of the workers API (only the job knows it).
resource "azurerm_api_management_named_value" "refresh_token" {
  name                = "RefreshToken"
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  display_name        = "RefreshToken"
  value               = random_password.refresh_token.result
  secret              = true
}

# ---------------------------------------------------------------------------
# API 1: workday-mock — the mocked downstream Workday. Returns sample workers.
# Public so the workers refresh branch can hairpin to it without a key. In a real
# deployment WorkdayBackendUrl points at Workday (OAuth), not this mock.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api" "mock" {
  name                  = "workday-mock"
  resource_group_name   = azurerm_resource_group.this.name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Workday Mock API"
  path                  = "workday-mock"
  protocols             = ["https"]
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "mock_get" {
  operation_id        = "get-workers"
  api_name            = azurerm_api_management_api.mock.name
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  display_name        = "Get Workers"
  method              = "GET"
  url_template        = "/workers"
  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "mock" {
  api_name            = azurerm_api_management_api.mock.name
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  xml_content = templatefile("${path.module}/policies/workday-mock.xml.tftpl", {
    workers_json = file("${path.module}/data/workers.json")
  })
  depends_on = [azurerm_api_management_api_operation.mock_get]
}

# ---------------------------------------------------------------------------
# API 2: workers — the active-cache endpoint. Serves ONLY from Redis on the read
# path (HIT/503). A refresh branch, gated by X-Refresh-Token, pulls a full load
# from Workday and cache-stores it THROUGH APIM (correct key namespace). This is
# what used to be a separate cache-admin API.
# Public (no subscription) so it is trivial to curl.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api" "workers" {
  name                  = "workers"
  resource_group_name   = azurerm_resource_group.this.name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Workers (cached)"
  path                  = "workers"
  protocols             = ["https"]
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "workers_get" {
  operation_id        = "get-cached-workers"
  api_name            = azurerm_api_management_api.workers.name
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  display_name        = "Get Cached Workers"
  method              = "GET"
  url_template        = "/"
  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "workers" {
  api_name            = azurerm_api_management_api.workers.name
  resource_group_name = azurerm_resource_group.this.name
  api_management_name = azurerm_api_management.this.name
  xml_content         = file("${path.module}/policies/workers-cache-read.xml")
  depends_on = [
    azurerm_api_management_api_operation.workers_get,
    azurerm_api_management_named_value.cache_key,
    azurerm_api_management_named_value.cache_ttl,
    azurerm_api_management_named_value.workday_backend_url,
    azurerm_api_management_named_value.refresh_token,
    azurerm_api_management_redis_cache.this,
  ]
}

# ---------------------------------------------------------------------------
# Container Apps Job — the active pre-filler (cron). No custom image/build:
# public alpine/curl + an inline script triggers the refresh (GET /workers with the token).
# ponytail: pulls alpine/curl from Docker Hub anonymously. If rate limits bite,
# push it to an ACR and point image/registry here.
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.base}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_container_app_environment" "this" {
  name                       = "cae-${local.base}"
  location                   = azurerm_resource_group.this.location
  resource_group_name        = azurerm_resource_group.this.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  tags                       = local.tags
}

resource "azurerm_container_app_job" "refresher" {
  name                         = "refresher-${local.token}"
  location                     = azurerm_resource_group.this.location
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  replica_timeout_in_seconds   = 120
  replica_retry_limit          = 1

  schedule_trigger_config {
    cron_expression          = var.refresh_cron
    parallelism              = 1
    replica_completion_count = 1
  }

  secret {
    name  = "refresh-token"
    value = random_password.refresh_token.result
  }

  template {
    container {
      name    = "refresher"
      image   = "docker.io/alpine/curl:latest"
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["/bin/sh", "-c"]
      args    = [file("${path.module}/../refresher/refresh.sh")]

      env {
        name  = "APIM_GATEWAY_URL"
        value = azurerm_api_management.this.gateway_url
      }
      env {
        name        = "REFRESH_TOKEN"
        secret_name = "refresh-token"
      }
    }
  }

  depends_on = [
    azurerm_api_management_api_policy.mock,
    azurerm_api_management_api_policy.workers,
  ]
}
