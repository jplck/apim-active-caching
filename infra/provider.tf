terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  # subscription_id is optional here: azd passes it via main.tfvars.json,
  # standalone users can set it in tfvars or export ARM_SUBSCRIPTION_ID.
  subscription_id = var.subscription_id
  features {}
}
