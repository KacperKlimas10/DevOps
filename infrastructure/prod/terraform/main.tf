/* CLOUDFLARE */

resource "cloudflare_zone" "parcel_platform_zone" {
  account = {
    id = var.cloudflare_account_id
  }
  name = var.cloudflare_domain_name
  type = "full"
}

resource "cloudflare_dns_record" "azure_vpn_dns_record" {
  name    = "vpn"
  ttl     = 1   # Auto TTL for proxied record
  type    = "A"
  proxied = true
  zone_id = cloudflare_zone.parcel_platform_zone.id
  comment = "A record for Azure VPN Gateway"
  content = azurerm_public_ip.vpn_public_ip.ip_address
}
resource "cloudflare_dns_record" "azure_blob_dns_record" {
  name    = "blob"
  ttl     = 1   # Auto TTL for proxied record
  type    = "CNAME"
  proxied = true
  zone_id = cloudflare_zone.parcel_platform_zone.id
  comment = "CNAME record for Azure Blob Storage"
  content = data.azurerm_storage_account.azure_storage_account.primary_blob_host
}

resource "cloudflare_dns_record" "azure_registry_dns_record" {
  name    = "registry"
  ttl     = 1   # Auto TTL for proxied record
  type    = "CNAME"
  proxied = true
  zone_id = cloudflare_zone.parcel_platform_zone.id
  comment = "CNAME record for Azure Container Registry"
  content = data.azurerm_container_registry.azure_container_registry.login_server
}

/* AZURE */

locals {
  env                      = var.azure_application_tags.env
  azure_resourcegroup_name = module.azure_naming.resource_group.name_unique
}

resource "azuread_application" "parcel_platform" {
  display_name = "parcelplatform"
  owners       = [data.azuread_client_config.parcel_platform.object_id]
}

resource "azuread_service_principal" "parcel_platform" {
  client_id                    = azuread_application.parcel_platform.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.parcel_platform.object_id]
  feature_tags {
    enterprise = true
    gallery    = true
  }
}

resource "azuread_service_principal_password" "parcel_platform" {
  service_principal_id = azuread_service_principal.parcel_platform.id
}

data "azuread_client_config" "parcel_platform" {}

module "azure_naming" {
  source  = "Azure/naming/azurerm"
  version = "0.4.2"
  suffix  = var.azure_application_suffix
}

module "azure_regions" {
  source        = "Azure/avm-utl-regions/azurerm"
  version       = "0.9.0"
  region_filter = [var.azure_region]
}

module "azure_resource_group" {
  source   = "Azure/avm-res-resources-resourcegroup/azurerm"
  version  = "0.2.1"
  name     = "${local.azure_resourcegroup_name}_${local.env}"
  location = var.azure_region
  tags     = var.azure_application_tags
}

resource "tls_private_key" "azure_aks_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_ssh_public_key" "azure_aks_key" {
  name                = "akskey"
  resource_group_name = module.azure_resource_group.name
  location            = var.azure_region
  public_key          = tls_private_key.azure_aks_key.public_key_openssh
  tags                = var.azure_application_tags
}

resource "azurerm_public_ip" "vpn_public_ip" {
  name                = module.azure_naming.public_ip.name_unique
  location            = var.azure_region
  resource_group_name = module.azure_resource_group.name
  allocation_method   = "Static"
  zones               = ["1", "2", "3"]
  tags                = var.azure_application_tags
}

resource "azurerm_virtual_network_gateway" "vpn_gateway" {
  name                = module.azure_naming.virtual_network_gateway.name_unique
  location            = var.azure_region
  resource_group_name = module.azure_resource_group.name
  type                = "Vpn"
  generation          = "Generation1"
  sku                 = "VpnGw2AZ"
  ip_configuration {
    public_ip_address_id = azurerm_public_ip.vpn_public_ip.id
    subnet_id            = module.azure_management_vnet.subnets["vpnsubnet"].resource_id
  }
  vpn_client_configuration {
    vpn_auth_types       = ["Certificate"]
    vpn_client_protocols = ["IkeV2", "OpenVPN"]
    address_space        = ["172.16.0.0/24"]
    root_certificate {
      name             = "ParcelPlatformCA"
      public_cert_data = replace(file(var.azure_vpn_path_to_cert), "/-.*-/", "")
    }
  }
  tags = var.azure_application_tags
}

module "azure_management_vnet" {
  source        = "Azure/avm-res-network-virtualnetwork/azurerm"
  version       = "0.11.0"
  address_space = ["10.1.0.0/24"]
  location      = var.azure_region
  dns_servers = {
    dns_servers = [
      "1.1.1.1", # Cloudflare DNS
      "1.0.0.1", # Cloudflare DNS
      "8.8.8.8"  # Google DNS
    ]
  }
  name      = "vnet-parcelplatform-management"
  parent_id = module.azure_resource_group.resource_id
  subnets = {
    "vpnsubnet" = {
      name             = "GatewaySubnet"
      address_prefixes = ["10.1.0.0/27"]
    }
  }
  tags = var.azure_application_tags
}

module "azure_node_vnet" {
  source        = "Azure/avm-res-network-virtualnetwork/azurerm"
  version       = "0.11.0"
  address_space = ["10.0.0.0/16"]
  location      = var.azure_region
  dns_servers = {
    dns_servers = [
      "1.1.1.1", # Cloudflare DNS
      "1.0.0.1", # Cloudflare DNS
      "8.8.8.8"  # Google DNS
    ]
  }
  name      = "vnet-parcelplatform-aks"
  parent_id = module.azure_resource_group.resource_id
  subnets = {
    "subnet1" = {
      name             = "vnet-subnet1"
      address_prefixes = ["10.0.0.0/24"]
      network_security_group = {
        id = module.azure_node_vnet_nsg.resource_id
      }
    }
    "subnet2" = {
      name             = "vnet-subnet2"
      address_prefixes = ["10.0.1.0/24"]
      network_security_group = {
        id = module.azure_node_vnet_nsg.resource_id
      }
    }
    "subnet3" = {
      name             = "vnet-subnet3"
      address_prefixes = ["10.0.2.0/24"]
      network_security_group = {
        id = module.azure_node_vnet_nsg.resource_id
      }
    }
  }
  tags = var.azure_application_tags
}

resource "azurerm_virtual_network_peering" "management_aks" {
  name                      = "management-aks"
  resource_group_name       = module.azure_resource_group.name
  virtual_network_name      = module.azure_management_vnet.name
  remote_virtual_network_id = module.azure_node_vnet.resource_id
  allow_gateway_transit     = true
}

resource "azurerm_virtual_network_peering" "aks_management" {
  name                      = "aks-management"
  resource_group_name       = module.azure_resource_group.name
  virtual_network_name      = module.azure_node_vnet.name
  remote_virtual_network_id = module.azure_management_vnet.resource_id
  use_remote_gateways       = true
}

module "azure_node_vnet_nsg" {
  source              = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version             = "0.5.0"
  location            = var.azure_region
  name                = "nsg-azure-node-vnet"
  resource_group_name = module.azure_resource_group.name
  security_rules = {
    rule1 = {
      name                       = "InboundWeb"
      priority                   = 100
      protocol                   = "Tcp"
      direction                  = "Inbound"
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_ranges    = ["80", "443"]
      source_address_prefix      = "Internet"
      source_port_range          = "*"
    }
    rule2 = {
      name                       = "InboundManagement"
      priority                   = 150
      protocol                   = "*"
      direction                  = "Inbound"
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_range     = "*"
      source_address_prefix      = "10.1.0.0/24"
      source_port_range          = "*"
    }
    rule4 = {
      name                       = "OutboundManagement"
      priority                   = 100
      protocol                   = "*"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "10.1.0.0/24"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
    rule5 = {
      name                       = "OutboundWeb"
      priority                   = 150
      protocol                   = "Tcp"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
  }
  tags = var.azure_application_tags
}


module "azure_aks" {
  source              = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version             = "0.3.0"
  location            = var.azure_region
  name                = module.azure_naming.kubernetes_cluster.name_unique
  resource_group_name = module.azure_resource_group.name
  sku_tier            = "Standard"
  default_node_pool = { # System Node VirtualMachineScaleSets
    name                 = "systemnode"
    vm_size              = "Standard_A4_v2" # 4 vCPU 8 GB
    os_sku               = "AzureLinux"
    auto_scaling_enabled = true
    min_count            = 1
    node_count           = 1
    max_count            = 3
    vnet_subnet_id       = module.azure_node_vnet.subnets["subnet1"].resource_id
    zones                = ["1", "2", "3"] # All Availability Zones
    tags                 = var.azure_application_tags
  }
  node_pools = {
    "node1" = { # User Node VirtualMachineScaleSets
      name                 = "usrnode1"
      vm_size              = "Standard_A4_v2" # 4 vCPU 8 GB
      os_sku               = "AzureLinux"
      auto_scaling_enabled = true
      min_count            = 1
      node_count           = 1
      max_count            = 3
      vnet_subnet_id       = module.azure_node_vnet.subnets["subnet2"].resource_id
      zones                = ["1", "2", "3"] # All Availability Zones
      tags                 = var.azure_application_tags
    }
    "node2" = { # User Node VirtualMachineScaleSets
      name                 = "usrnode2"
      vm_size              = "Standard_A2_v2" # 2 vCPU 4 GB
      os_sku               = "AzureLinux"
      auto_scaling_enabled = true
      min_count            = 1
      node_count           = 1
      max_count            = 3
      vnet_subnet_id       = module.azure_node_vnet.subnets["subnet3"].resource_id
      zones                = ["1", "2", "3"] # All Availability Zones
      tags                 = var.azure_application_tags
    }
  }
  network_profile = {
    network_plugin      = "azure",
    network_plugin_mode = "overlay",
    network_policy      = "azure"
    dns_service_ip      = "172.16.0.10"
    service_cidr        = "172.16.0.0/24"
    pod_cidr            = "172.17.0.0/16"
  }
  dns_prefix = "parcelplatform"
  linux_profile = {
    admin_username = "parcelplatform_admin"
    ssh_key        = azurerm_ssh_public_key.azure_aks_key.public_key
  }
  service_principal = {
    client_id     = azuread_service_principal.parcel_platform.client_id
    client_secret = azuread_service_principal_password.parcel_platform.value
  }
  local_account_disabled = false
  tags                   = var.azure_application_tags
}

module "azure_storage_account" {
  source                   = "Azure/avm-res-storage-storageaccount/azurerm"
  version                  = "0.6.4"
  location                 = var.azure_region
  name                     = "parcelplatformblob"
  resource_group_name      = module.azure_resource_group.name
  access_tier              = "Hot"
  account_kind             = "BlobStorage"
  account_replication_type = "LRS"
  tags                     = var.azure_application_tags
}

data "azurerm_storage_account" "azure_storage_account" {
  name                = module.azure_storage_account.name
  resource_group_name = module.azure_resource_group.name
  depends_on          = [module.azure_storage_account]
}

module "azure_container_registry" {
  source                  = "Azure/avm-res-containerregistry-registry/azurerm"
  version                 = "0.5.0"
  location                = var.azure_region
  name                    = module.azure_naming.container_registry.name_unique
  resource_group_name     = module.azure_resource_group.name
  sku                     = "Premium"
  zone_redundancy_enabled = true
  tags                    = var.azure_application_tags
}

data "azurerm_container_registry" "azure_container_registry" {
  name                = module.azure_container_registry.name
  resource_group_name = module.azure_resource_group.name
  depends_on          = [module.azure_container_registry]
}

/* HELM */

resource "helm_release" "argo_cd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.0.5"
  namespace        = "argocd"
  create_namespace = true
  depends_on = [module.azure_aks]
}