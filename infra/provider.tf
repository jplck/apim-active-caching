terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "azurerm" {
  # subscription_id is optional here: azd passes it via main.tfvars.json,
  # standalone users can set it in tfvars or export ARM_SUBSCRIPTION_ID.
  subscription_id = var.subscription_id
  features {}
}

# azuread is declared alongside azurerm for Entra directory operations tied to
# the MI-only auth model (Postgres Entra admin / DB principals). Inherits the
# az login / ARM environment.
provider "azuread" {}
