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
