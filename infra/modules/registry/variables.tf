variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "token" {
  type        = string
  description = "Stable random suffix for the globally-unique ACR name."
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "middleware_principal_id" {
  type = string
}

variable "refresher_principal_id" {
  type = string
}

variable "enable_private_networking" {
  type        = bool
  default     = false
  description = "When true, put ACR behind a private endpoint (requires the Premium SKU) and disable public network access."
}

variable "private_endpoint_subnet_id" {
  type        = string
  default     = null
  description = "Subnet id for the ACR private endpoint. Required when enable_private_networking is true."
}

variable "private_dns_zone_id" {
  type        = string
  default     = null
  description = "privatelink.azurecr.io private DNS zone id linked to the VNet. Required when enable_private_networking is true."
}
