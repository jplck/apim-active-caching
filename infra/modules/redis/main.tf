terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Azure Managed Redis (external cache for APIM)
# Classic Azure Cache for Redis is retired for new creates, so this uses Azure
# Managed Redis on the cheapest Balanced_B0 SKU. EnterpriseCluster policy exposes
# a single, non-clustered endpoint that APIM's StackExchange.Redis client connects
# to with a plain connection string (no cluster redirects).
# access_keys_authentication_enabled = true so the connection string can use a key.
# ---------------------------------------------------------------------------
resource "azurerm_managed_redis" "this" {
  name                      = "redis-${var.base}"
  location                  = var.location
  resource_group_name       = var.resource_group_name
  sku_name                  = var.redis_sku
  high_availability_enabled = false
  tags                      = var.tags

  # azurerm_managed_redis exposes public access as a string toggle
  # (public_network_access = "Enabled"/"Disabled"), not a bool. When private
  # networking is enabled we turn public access off; the private endpoint below
  # provides the private path. Flag off keeps the "Enabled" default (no-op).
  public_network_access = var.enable_private_networking ? "Disabled" : "Enabled"

  default_database {
    clustering_policy                  = "EnterpriseCluster"
    client_protocol                    = "Encrypted"
    access_keys_authentication_enabled = true
  }
}

# ---------------------------------------------------------------------------
# Optional private endpoint (opt-in via enable_private_networking). Projects the
# Managed Redis (redisEnterprise) endpoint into the private-endpoints subnet and
# registers its A record in privatelink.redis.azure.net so in-VNet clients (APIM
# external cache) resolve the private IP. Flag off => count 0, a pure no-op.
# ---------------------------------------------------------------------------
resource "azurerm_private_endpoint" "redis" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "pe-redis-${var.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-redis-${var.base}"
    private_connection_resource_id = azurerm_managed_redis.this.id
    is_manual_connection           = false
    subresource_names              = ["redisEnterprise"]
  }

  private_dns_zone_group {
    name                 = "redis"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
