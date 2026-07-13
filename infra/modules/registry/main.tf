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
resource "azurerm_container_registry" "this" {
  name                = "acr${var.token}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = var.tags
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
