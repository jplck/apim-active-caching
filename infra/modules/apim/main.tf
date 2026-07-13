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
