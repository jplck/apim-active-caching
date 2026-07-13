terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# Two user-assigned managed identities — one per workload. User-assigned (not
# system-assigned) so their principal ids exist *before* the Container Apps are
# created, letting us pre-provision them as Postgres Entra DB roles and grant
# AcrPull / Key Vault access without a chicken-and-egg dependency.
resource "azurerm_user_assigned_identity" "middleware" {
  name                = "id-middleware-${var.base}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "refresher" {
  name                = "id-refresher-${var.base}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
