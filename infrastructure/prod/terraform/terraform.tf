terraform {
  required_version = "~> 1.14.1"
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.10.1"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.45.1"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.6"
    }
  }
}
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "azurerm" {
  subscription_id     = var.azure_subscription_id
  storage_use_azuread = true
  features {}
}

provider "helm" {
  kubernetes = {
    host                   = module.azure_aks.host
    client_certificate     = base64decode(module.azure_aks.kube_config[0].client_certificate)
    client_key             = base64decode(module.azure_aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(module.azure_aks.cluster_ca_certificate)
  }
}