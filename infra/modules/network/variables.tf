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

variable "enable_private_networking" {
  type        = bool
  description = "Master gate. When false the whole module is inert (no VNet, subnets or DNS zones) and every output is null."
  default     = false
}

variable "vnet_address_space" {
  type        = string
  description = "CIDR for the single VNet."
  default     = "10.20.0.0/16"
}

variable "apim_integration_subnet_cidr" {
  type        = string
  description = "Subnet for APIM Std v2 outbound VNet integration (delegated to Microsoft.Web/serverFarms)."
  default     = "10.20.0.0/24"
}

variable "aca_infrastructure_subnet_cidr" {
  type        = string
  description = "Container Apps environment infrastructure subnet (delegated to Microsoft.App/environments)."
  default     = "10.20.4.0/23"
}

variable "pe_subnet_cidr" {
  type        = string
  description = "Private-endpoint subnet (no delegation)."
  default     = "10.20.8.0/24"
}
