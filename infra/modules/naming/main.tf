terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Single source of truth for resource names and tags. Every other module derives
# its names from `base` (env name + a stable random suffix) and stamps `tags`
# (azd needs the azd-env-name tag to associate resources with the environment).
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  token = lower(random_string.suffix.result)
  base  = "${var.environment_name}-${local.token}"
  tags  = { "azd-env-name" = var.environment_name }
}
