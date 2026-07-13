terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Private networking foundation (OPTIONAL — plan.md §10).
#
# Everything here is gated by `count = var.enable_private_networking ? 1 : 0`
# so that the default public POC is byte-for-byte unchanged: with the flag off
# no VNet, subnets or private DNS zones are created and every output is null.
#
# Topology (see plan.md §10.2):
#   * one VNet
#   * snet-apim-out  — APIM Std v2 outbound VNet integration (delegated)
#   * snet-aca       — Container Apps environment infrastructure subnet (delegated)
#   * snet-pe        — private endpoints for Postgres/Redis/KeyVault/ACR (no delegation)
#   * five privatelink.* private DNS zones, each linked to the VNet
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "vnet-${var.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.vnet_address_space]
  tags                = var.tags
}

# APIM Std v2 outbound VNet integration subnet — delegated to serverFarms.
resource "azurerm_subnet" "apim_integration" {
  count                = var.enable_private_networking ? 1 : 0
  name                 = "snet-apim-out"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.apim_integration_subnet_cidr]

  delegation {
    name = "apim-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Container Apps environment infrastructure subnet — delegated to App/environments.
resource "azurerm_subnet" "aca_infrastructure" {
  count                = var.enable_private_networking ? 1 : 0
  name                 = "snet-aca"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.aca_infrastructure_subnet_cidr]

  delegation {
    name = "aca-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Private-endpoint subnet — plain, no delegation.
resource "azurerm_subnet" "pe" {
  count                = var.enable_private_networking ? 1 : 0
  name                 = "snet-pe"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.pe_subnet_cidr]
}

# ---------------------------------------------------------------------------
# Private DNS zones — one per privatelink FQDN, each linked to the VNet so that
# private FQDNs resolve to private IPs from inside the VNet.
# ---------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "apim" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.azure-api.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "apim-${var.base}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.apim[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone" "postgres" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "postgres-${var.base}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone" "redis" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.redis.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "redis-${var.base}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.redis[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone" "keyvault" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "keyvault-${var.base}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count                 = var.enable_private_networking ? 1 : 0
  name                  = "acr-${var.base}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = azurerm_virtual_network.this[0].id
  tags                  = var.tags
}
