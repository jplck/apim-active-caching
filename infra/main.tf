# ---------------------------------------------------------------------------
# Root composition. Wires the modules together and owns the resource group +
# shared data sources. Cross-module IAM: the only role assignments here are the
# ones that would otherwise create module cycles; the Key Vault Secrets User and
# AcrPull grants live in the keyvault/registry modules because they depend only
# on `identity` (a leaf) and so are cycle-free. The Postgres Entra DB roles are
# bootstrapped inside the postgres module. Hence no extra IAM is needed here.
# ---------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

module "naming" {
  source           = "./modules/naming"
  environment_name = var.environment_name
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.environment_name}"
  location = var.location
  tags     = module.naming.tags
}

module "identity" {
  source              = "./modules/identity"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  base                = module.naming.base
  tags                = module.naming.tags
}

module "keyvault" {
  source                 = "./modules/keyvault"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  token                  = module.naming.token
  tags                   = module.naming.tags
  workday_username       = var.workday_username
  workday_password       = var.workday_password
  refresher_principal_id = module.identity.refresher_principal_id
}

module "registry" {
  source                  = "./modules/registry"
  resource_group_name     = azurerm_resource_group.this.name
  location                = azurerm_resource_group.this.location
  token                   = module.naming.token
  tags                    = module.naming.tags
  middleware_principal_id = module.identity.middleware_principal_id
  refresher_principal_id  = module.identity.refresher_principal_id
}

module "redis" {
  source              = "./modules/redis"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  base                = module.naming.base
  tags                = module.naming.tags
  redis_sku           = var.redis_sku
}

module "postgres" {
  source                  = "./modules/postgres"
  resource_group_name     = azurerm_resource_group.this.name
  location                = azurerm_resource_group.this.location
  base                    = module.naming.base
  tags                    = module.naming.tags
  tenant_id               = data.azurerm_client_config.current.tenant_id
  postgres_sku            = var.postgres_sku
  postgres_storage_mb     = var.postgres_storage_mb
  middleware_principal_id = module.identity.middleware_principal_id
  refresher_principal_id  = module.identity.refresher_principal_id
  entra_admin_object_id   = var.entra_admin_object_id
}

# The refresher's Workday source. When workday_soap_url is empty we fall back to
# the in-APIM SOAP mock. We build that URL from the *deterministic* APIM hostname
# (apim-<base>.azure-api.net) rather than from module.apim's output, which breaks
# the containerapps -> apim -> containerapps cycle (apim needs the middleware URL).
locals {
  apim_gateway_url           = "https://apim-${module.naming.base}.azure-api.net"
  workday_soap_url_effective = var.workday_soap_url != "" ? var.workday_soap_url : "${local.apim_gateway_url}/workday-soap/Human_Resources"
}

module "containerapps" {
  source              = "./modules/containerapps"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  base                = module.naming.base
  token               = module.naming.token
  tags                = module.naming.tags

  acr_login_server = module.registry.login_server

  middleware_identity_id = module.identity.middleware_id
  middleware_client_id   = module.identity.middleware_client_id
  refresher_identity_id  = module.identity.refresher_id
  refresher_client_id    = module.identity.refresher_client_id

  postgres_fqdn     = module.postgres.fqdn
  postgres_port     = module.postgres.port
  postgres_database = module.postgres.database_name
  middleware_role   = module.postgres.middleware_role
  refresher_role    = module.postgres.refresher_role

  workday_username_secret_id = module.keyvault.username_secret_id
  workday_password_secret_id = module.keyvault.password_secret_id

  refresh_cron     = var.refresh_cron
  workday_soap_url = local.workday_soap_url_effective
}

module "apim" {
  source              = "./modules/apim"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  base                = module.naming.base
  tags                = module.naming.tags
  apim_sku            = var.apim_sku
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  cache_ttl_seconds   = var.cache_ttl_seconds

  redis_hostname = module.redis.hostname
  redis_port     = module.redis.port

  middleware_url = module.containerapps.middleware_url
}
