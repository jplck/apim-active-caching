variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "base" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "apim_sku" {
  type    = string
  default = "StandardV2_1"
}

variable "publisher_name" {
  type    = string
  default = "Contoso"
}

variable "publisher_email" {
  type    = string
  default = "admin@example.com"
}

variable "cache_ttl_seconds" {
  type    = number
  default = 172800
}

# --- external redis cache -------------------------------------------------
variable "redis_hostname" {
  type = string
}

variable "redis_port" {
  type = number
}

# --- workers backend ------------------------------------------------------
variable "middleware_url" {
  type        = string
  description = "Middleware Container App URL used as the workers backend + OpenAPI source."
}

# --- private networking (OPTIONAL, plan.md §10) ---------------------------
# Shared contract inputs passed verbatim by the root module. Everything is gated
# by enable_private_networking; when it is false this module behaves exactly like
# the public POC (no private endpoint, no VNet wiring). The public gateway always
# stays reachable — we never disable public network access (§10.1/§10.5).
variable "enable_private_networking" {
  type        = bool
  default     = false
  description = "Opt-in flag (§10) that ADDS private access to APIM. Public gateway access always stays enabled."
}

variable "private_endpoint_subnet_id" {
  type        = string
  default     = null
  description = "Subnet ID for the inbound APIM Gateway private endpoint (client -> APIM private IP)."
}

variable "apim_private_dns_zone_id" {
  type        = string
  default     = null
  description = "privatelink.azure-api.net private DNS zone ID linked to the inbound private endpoint."
}

variable "integration_subnet_id" {
  type        = string
  default     = null
  description = "Delegated (Microsoft.Web/serverFarms) subnet for Std v2 outbound VNet integration (APIM -> private backends). Declared for the root contract; unused in TF — see the provider-limitation note in main.tf."
}
