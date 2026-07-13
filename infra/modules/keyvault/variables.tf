variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "token" {
  type        = string
  description = "Stable random suffix for the globally-unique, <=24-char vault name."
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "workday_username" {
  type        = string
  description = "Workday ISU username stored as the workday-username secret."
  sensitive   = true
}

variable "workday_password" {
  type        = string
  description = "Workday ISU password stored as the workday-password secret."
  sensitive   = true
}

variable "refresher_principal_id" {
  type        = string
  description = "Principal id of the refresher identity granted Key Vault Secrets User."
}

# Optional private-networking inputs (root passes these exact names/types).
# Default off so the public POC path is completely unchanged.
variable "enable_private_networking" {
  type        = bool
  default     = false
  description = "When true, lock the vault to the VNet: no public access, Deny network_acls, and a private endpoint."
}

variable "private_endpoint_subnet_id" {
  type        = string
  default     = null
  description = "Subnet id (snet-pe) hosting the Key Vault private endpoint. Required when enable_private_networking = true."
}

variable "private_dns_zone_id" {
  type        = string
  default     = null
  description = "privatelink.vaultcore.azure.net private DNS zone id for the endpoint's zone group. Required when enable_private_networking = true."
}
