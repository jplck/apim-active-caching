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
