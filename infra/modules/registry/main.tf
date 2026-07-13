terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Azure Container Registry for the middleware + refresher images that azd builds
# and pushes. Name must be globally unique and alphanumeric only, so we strip
# separators from the token-based name.
#
# SKU note: ACR Private Link (private endpoints) is a Premium-only feature, so we
# must bump the SKU to Premium whenever private networking is enabled; the public
# POC path stays on Basic to keep costs down.
#
# Build/push caveat: with public_network_access_enabled = false the registry is
# only reachable over the VNet, so `azd`/`az acr build` image pushes need VNet
# reachability. Keep ACR public for the first build (leave enable_private_networking
# off during the initial `azd up`), or push from a VNet-connected runner / ACR Tasks
# before flipping it private. See plan.md §10.5.
resource "azurerm_container_registry" "this" {
  name                          = "acr${var.token}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.enable_private_networking ? "Premium" : "Basic"
  admin_enabled                 = false
  public_network_access_enabled = !var.enable_private_networking
  tags                          = var.tags
}

# Private endpoint that projects ACR into the VNet's private-endpoint subnet and
# wires up the privatelink.azurecr.io A record so Container Apps resolve the
# registry to a private IP and pull images over the VNet.
resource "azurerm_private_endpoint" "acr" {
  count = var.enable_private_networking ? 1 : 0

  name                = "pe-acr${var.token}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-acr${var.token}"
    private_connection_resource_id = azurerm_container_registry.this.id
    is_manual_connection           = false
    subresource_names              = ["registry"]
  }

  private_dns_zone_group {
    name                 = "registry"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}

# Both workload identities pull their images from ACR via AcrPull (no admin user,
# no registry password). These assignments only depend on `identity`, so keeping
# them in this module creates no dependency cycle.
resource "azurerm_role_assignment" "middleware_acrpull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = var.middleware_principal_id
}

resource "azurerm_role_assignment" "refresher_acrpull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = var.refresher_principal_id
}
