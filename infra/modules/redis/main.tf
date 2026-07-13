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

  default_database {
    clustering_policy                  = "EnterpriseCluster"
    client_protocol                    = "Encrypted"
    access_keys_authentication_enabled = true
  }
}
