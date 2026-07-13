terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# ---------------------------------------------------------------------------
# API Management (Standard v2)
# ---------------------------------------------------------------------------
resource "azurerm_api_management" "this" {
  name                = "apim-${var.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku
  tags                = var.tags
}

# Wire Azure Managed Redis as APIM's external cache. cache_location "default" =
# usable from any region. Port + ssl is the Managed Redis endpoint. The
# connection-string pattern mirrors the proven wiring from the original infra.
resource "azurerm_api_management_redis_cache" "active" {
  name              = "default"
  api_management_id = azurerm_api_management.this.id
  connection_string = "${var.redis_hostname}:${var.redis_port},******"
  cache_location    = "default"
}

# TTL for the passive cache-store-value, single source of truth via a TF var.
resource "azurerm_api_management_named_value" "cache_ttl" {
  name                = "CacheTtlSeconds"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  display_name        = "CacheTtlSeconds"
  value               = tostring(var.cache_ttl_seconds)
}

# ---------------------------------------------------------------------------
# API: workday-mock-soap — the mocked Workday SOAP (Human_Resources / Get_Workers)
# endpoint. POST returns a static Get_Workers_Response envelope. Kept as the
# refresher's Workday source for the POC (real deploy repoints WORKDAY_SOAP_URL).
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api" "mock_soap" {
  name                  = "workday-mock-soap"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Workday Mock SOAP API"
  path                  = "workday-soap"
  protocols             = ["https"]
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "mock_soap_get" {
  operation_id        = "get-workers"
  api_name            = azurerm_api_management_api.mock_soap.name
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  display_name        = "Get_Workers"
  method              = "POST"
  url_template        = "/Human_Resources"
  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "mock_soap" {
  api_name            = azurerm_api_management_api.mock_soap.name
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  xml_content = templatefile("${path.module}/policies/workday-mock-soap.xml.tftpl", {
    workers_soap = file("${path.module}/data/workers-soap.xml")
  })
  depends_on = [azurerm_api_management_api_operation.mock_soap_get]
}

# ---------------------------------------------------------------------------
# API: workday-mock — trivial REST mock kept for demos. Returns a static payload.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api" "mock" {
  name                  = "workday-mock"
  resource_group_name   = var.resource_group_name
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
  resource_group_name = var.resource_group_name
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
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  xml_content = templatefile("${path.module}/policies/workday-mock.xml.tftpl", {
    workers_json = file("${path.module}/data/workers.json")
  })
  depends_on = [azurerm_api_management_api_operation.mock_get]
}

# ---------------------------------------------------------------------------
# API: workers — the passively-cached Workday adapter. Imported from the
# middleware's OpenAPI; backend = middleware Container App URL. Empty path so the
# middleware's own routes (/workers, /workers/{id}, /healthz) sit at the gateway
# root. NOTE (apply-time): the middleware must be serving /openapi.json when this
# import runs — azd deploys the middleware image before `azd provision` completes
# the import, or provision the middleware first.
# ---------------------------------------------------------------------------
resource "azurerm_api_management_api" "workers" {
  name                  = "workers"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Workers"
  path                  = ""
  protocols             = ["https"]
  subscription_required = false
  service_url           = var.middleware_url

  import {
    content_format = "openapi+json-link"
    content_value  = "${var.middleware_url}/openapi.json"
  }
}

# Standard passive request/response caching over the external Redis cache.
resource "azurerm_api_management_api_policy" "workers" {
  api_name            = azurerm_api_management_api.workers.name
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  xml_content         = file("${path.module}/policies/workers-passive-cache.xml")
  depends_on = [
    azurerm_api_management_api.workers,
    azurerm_api_management_named_value.cache_ttl,
    azurerm_api_management_redis_cache.active,
  ]
}

# ---------------------------------------------------------------------------
# Private networking (OPTIONAL — plan.md §10). Everything here is gated by
# var.enable_private_networking, so flag-off is a complete no-op. The public
# gateway ALWAYS stays reachable: we deliberately never set
# publicNetworkAccess=Disabled (that Std v2 switch is a separate post-create
# PATCH and would break public API access — §10.1 / §10.5).
#
# §10.1 — on Standard v2 these are TWO SEPARATE, one-directional features; do
# NOT conflate them:
#   * Inbound private endpoint  (client -> APIM): projects the gateway as a
#     private IP inside the VNet, while public access stays ON. Implemented below.
#   * Outbound VNet integration (APIM -> backend): lets APIM reach the private
#     middleware over the VNet. This is NOT a private endpoint and is a separate
#     feature — see the provider-limitation note below.
# A single injected model that carries BOTH directions on one delegated subnet
# only exists on Premium v2 (VNet injection); Standard v2 splits the capability
# into the two gateway-only halves above.
# ---------------------------------------------------------------------------

# --- Outbound VNet integration (Standard v2) — PROVIDER LIMITATION ----------
# §10.3 wants APIM to reach the private middleware via Std v2 outbound VNet
# integration (the "integrate-vnet-outbound" feature: a subnet delegated to
# Microsoft.Web/serverFarms). azurerm ~> 4.0 does NOT model this yet.
#
# Verified against the provider source (SDK apimanagementservice 2024-05-01):
# the ONLY VNet arguments on azurerm_api_management are `virtual_network_type`
# (None/External/Internal) + `virtual_network_configuration { subnet_id }`.
# Those are the CLASSIC injection model (Developer/Premium, requires port 3443)
# — Azure rejects them for the StandardV2 SKU and they do NOT configure v2
# outbound integration. There is no azurerm argument for the v2 feature yet
# (ref: hashicorp/terraform-provider-azurerm #24377 only added the v2 SKU names).
#
# Per the fleet rules we do NOT hack this in and do NOT add azapi. The
# `integration_subnet_id` variable is declared (variables.tf) so the root wiring
# validates, but is intentionally UNUSED here. Enable outbound integration
# MANUALLY after deploy, pointing APIM at the delegated subnet
# var.integration_subnet_id (which must be delegated to Microsoft.Web/serverFarms):
#   Portal: APIM -> Network -> Outbound features -> enable "Virtual network
#           integration" -> select the delegated subnet -> Save.
#   CLI   : PATCH the service via `az rest` using an API version that supports the
#           v2 feature, setting outbound integration onto integration_subnet_id.
# Docs: https://learn.microsoft.com/azure/api-management/integrate-vnet-outbound
# ---------------------------------------------------------------------------

# --- Inbound private endpoint (Standard v2, Gateway sub-resource) -----------
# client -> APIM private IP. Public gateway access is unchanged (purely additive).
# On Std v2 the private endpoint covers the GATEWAY only (not the management or
# developer-portal endpoints — those would need Premium v2 injection; §10.5).
resource "azurerm_private_endpoint" "apim" {
  count               = var.enable_private_networking ? 1 : 0
  name                = "pe-apim-${var.base}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "apim-gateway"
    private_connection_resource_id = azurerm_api_management.this.id
    is_manual_connection           = false
    subresource_names              = ["Gateway"]
  }

  private_dns_zone_group {
    name                 = "apim"
    private_dns_zone_ids = [var.apim_private_dns_zone_id]
  }
}
