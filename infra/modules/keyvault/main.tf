terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

data "azurerm_client_config" "current" {}

# Key Vault holding the Workday ISU credentials the refresher presents over
# WS-Security. RBAC authorization (not access policies) so grants are plain Azure
# role assignments. Name is capped at 24 chars via the short random token.
resource "azurerm_key_vault" "this" {
  name                       = "kv-${var.token}"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = var.tags

  # Flag-off (default) keeps public access on; flag-on turns it off so the data
  # plane is reachable only through the private endpoint below.
  public_network_access_enabled = !var.enable_private_networking

  # Only emitted when private: deny public traffic while still letting trusted
  # Azure services through (bypass). The dynamic block is absent when disabled,
  # so today's behavior (no ACLs, implicit Allow) is preserved exactly.
  dynamic "network_acls" {
    for_each = var.enable_private_networking ? [1] : []
    content {
      default_action = "Deny"
      bypass         = "AzureServices"
    }
  }
}

# Let the deploying principal write the secret material (RBAC vaults require an
# explicit data-plane role even for the vault creator).
resource "azurerm_role_assignment" "deployer_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The refresher identity only needs read access; the Container Apps platform uses
# it to resolve the KV secret references into container secrets at startup.
resource "azurerm_role_assignment" "refresher_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.refresher_principal_id
}

# Secret values come from sensitive Terraform variables — never hardcoded.
resource "azurerm_key_vault_secret" "workday_username" {
  name         = "workday-username"
  value        = var.workday_username
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.deployer_secrets_officer]
}

resource "azurerm_key_vault_secret" "workday_password" {
  name         = "workday-password"
  value        = var.workday_password
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.deployer_secrets_officer]
}

# Private endpoint projecting the vault into snet-pe and wiring the
# privatelink.vaultcore.azure.net zone so in-VNet callers resolve a private IP.
# Only created when private networking is enabled.
#
# APPLY-TIME CAVEAT (see plan.md §10.5): once public_network_access_enabled=false
# and network_acls default_action=Deny are in effect, both the deployer that
# writes the two workday-* secrets above and the Container Apps platform that
# resolves the KV secret references must reach the vault over the VNet through
# this endpoint. bypass=AzureServices lets trusted Azure services in, but the
# Terraform deployer may still need to run from a VNet-connected runner (or be
# granted a temporary network allow) for the secret writes to succeed. Secret
# creation itself is deliberately left unchanged.
resource "azurerm_private_endpoint" "kv" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "pe-kv-${var.token}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv-${var.token}"
    private_connection_resource_id = azurerm_key_vault.this.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "keyvault"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
