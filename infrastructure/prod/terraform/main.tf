/* CLOUDFLARE */

resource "cloudflare_dns_record" "azure_vpn_dns_record" {
  name    = "vpn-${local.env}"
  ttl     = 1 # Auto
  type    = "A"
  proxied = false # Cloudflare proxy is blocking some protocols used to vpn connection
  zone_id = var.cloudflare_dns_zone_id
  comment = "A record for Azure VPN Gateway"
  content = azurerm_public_ip.vpn_public_ip.ip_address
}

resource "cloudflare_dns_record" "azure_blob_dns_record" {
  name    = "blob-${local.env}"
  ttl     = 1 # Auto TTL for proxied record
  type    = "CNAME"
  proxied = true
  zone_id = var.cloudflare_dns_zone_id
  comment = "CNAME record for Azure Blob Storage"
  content = data.azurerm_storage_account.azure_storage_account.primary_blob_host
}

resource "cloudflare_dns_record" "azure_registry_dns_record" {
  name    = "registry-${local.env}"
  ttl     = 1 # Auto TTL for proxied record
  type    = "CNAME"
  proxied = true
  zone_id = var.cloudflare_dns_zone_id
  comment = "CNAME record for Azure Container Registry"
  content = data.azurerm_container_registry.azure_container_registry.login_server
}

/* AZURE */

locals {
  env                      = var.azure_application_tags.env
  azure_resourcegroup_name = module.azure_naming.resource_group.name_unique
}

# General AD Application
resource "azuread_application" "devops" {
  display_name = "devops"
  owners       = [data.azuread_client_config.devops.object_id]
}

# Azure AD for Kubernetes Cluster
resource "azuread_service_principal" "devops" {
  client_id                    = azuread_application.devops.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.devops.object_id]
  feature_tags {
    enterprise = true
    gallery    = true
  }
}

resource "azuread_service_principal_password" "devops" {
  service_principal_id = azuread_service_principal.devops.id
}

data "azuread_client_config" "devops" {} # Data about default Azure user

# Azure Identity for Azure Key Vault
resource "azurerm_user_assigned_identity" "devops_key_vault" {
  name                = "keyvault"
  resource_group_name = module.azure_resource_group.name
  location            = var.azure_region
  tags                = var.azure_application_tags
}

resource "azurerm_federated_identity_credential" "devops_key_vault" {
  name                = "kubernetes-federated-credential"
  parent_id           = azurerm_user_assigned_identity.devops_key_vault.id
  resource_group_name = module.azure_resource_group.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.azure_aks.oidc_issuer_url # OIDC Issuer from Kubernetes Cluster
  subject             = "system:serviceaccount:external-secrets:key-vault-integration"
}

# Azure Resources
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
      name             = "devopsCA"
      public_cert_data = replace(file(var.azure_vpn_path_to_cert), "/-.*-/", "")
    }
  }
  tags = var.azure_application_tags
}

module "azure_management_vnet" {
  source        = "Azure/avm-res-network-virtualnetwork/azurerm"
  version       = "0.11.0"
  address_space = ["10.1.0.0/16"]
  location      = var.azure_region
  # dns_servers = { # Isn't working correct with Private DNS Zone so I had to use default Azure DNS Server
  #   dns_servers = [
  #     "1.1.1.1",      # Cloudflare DNS
  #     "1.0.0.1",      # Cloudflare DNS
  #     "8.8.8.8",      # Google DNS
  #     "168.63.129.16" # Azure DNS Service
  #   ]
  # }
  name      = "vnet-devops-management"
  parent_id = module.azure_resource_group.resource_id
  subnets = {
    "vpnsubnet" = {
      name             = "GatewaySubnet"
      address_prefixes = ["10.1.0.0/27"]
    }
    "endpointsubnet" = {
      name             = "PrivateEndpointSubnet"
      address_prefixes = ["10.1.1.0/24"]
      network_security_group = {
        id = module.azure_management_vnet_nsg.resource_id
      }
    }
  }
  tags = var.azure_application_tags
}

module "azure_node_vnet" {
  source        = "Azure/avm-res-network-virtualnetwork/azurerm"
  version       = "0.11.0"
  address_space = ["10.0.0.0/16"]
  location      = var.azure_region
  # dns_servers = { # Isn't working correct with Private DNS Zone so I had to use default Azure DNS Server
  #   dns_servers = [   # All VMs that are connected to the virtual network register with the DNS servers that you specify for the virtual network.
  #     "1.1.1.1",      # Cloudflare DNS
  #     "1.0.0.1",      # Cloudflare DNS
  #     "8.8.8.8",      # Google DNS
  #     "168.63.129.16" # Azure DNS Service
  #   ]
  # }
  name      = "vnet-devops-aks"
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
      name                       = "InboundWebTCP"
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
      source_address_prefix      = "10.1.0.0/27" # Allow only from VPN clients
      source_port_range          = "*"
    }
    rule4 = {
      name                       = "OutboundWebTCP"
      priority                   = 100
      protocol                   = "Tcp"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_ranges    = ["80", "443", "53"] # HTTP, HTTPS, DNS TCP
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
    rule5 = {
      name                       = "OutboundWebUDP"
      priority                   = 150
      protocol                   = "Udp"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_range     = "53" # DNS UDP
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
    rule6 = {
      name                       = "OutboundManagement"
      priority                   = 200
      protocol                   = "*"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "10.1.0.0/27" # Allow only from VPN clients
      destination_port_range     = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
    rule6 = {
      name                       = "OutboundPrivateEndpoint"
      priority                   = 250
      protocol                   = "*"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "10.1.1.0/24" # Allow Traffic from Private Endpoint Subnet
      destination_port_range     = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
  }
  tags = var.azure_application_tags
}

module "azure_management_vnet_nsg" {
  source              = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version             = "0.5.0"
  location            = var.azure_region
  name                = "nsg-azure-management-vnet"
  resource_group_name = module.azure_resource_group.name
  security_rules = {
    rule1 = {
      name                       = "InboundNode"
      priority                   = 150
      protocol                   = "*"
      direction                  = "Inbound"
      access                     = "Allow"
      destination_address_prefix = "*"
      destination_port_range     = "*"
      source_address_prefix      = "10.0.0.0/16" # Allow only from Node VNet
      source_port_range          = "*"
    }
    rule2 = {
      name                       = "OutboundWebTCP"
      priority                   = 100
      protocol                   = "Tcp"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_ranges    = ["80", "443", "53"] # HTTP, HTTPS, DNS TCP
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
    rule3 = {
      name                       = "OutboundWebUDP"
      priority                   = 150
      protocol                   = "Udp"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "Internet"
      destination_port_range     = "53" # DNS UDP
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
    rule4 = {
      name                       = "OutboundNode"
      priority                   = 200
      protocol                   = "*"
      direction                  = "Outbound"
      access                     = "Allow"
      destination_address_prefix = "10.0.0.0/16" # Allow from
      destination_port_range     = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
    }
  }
  tags = var.azure_application_tags
}

module "azure_aks" {
  source                    = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version                   = "0.3.0"
  location                  = var.azure_region
  name                      = module.azure_naming.kubernetes_cluster.name_unique
  resource_group_name       = module.azure_resource_group.name
  node_resource_group_name  = "rg_devopsproject_node_${local.env}"
  sku_tier                  = "Standard"
  workload_identity_enabled = true # Enable Workload Identity for Key Vault
  oidc_issuer_enabled       = true # For integration with other cloud resources we need to enable OpenID Connect authentication
  default_node_pool = {            # System Node VirtualMachineScaleSets
    name                 = "systemnode"
    vm_size              = "Standard_D2ds_v4" # 2 vCPU 8 GB
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
      vm_size              = "Standard_D2ds_v4" # 2 vCPU 4 GB
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
      vm_size              = "Standard_D2ds_v4" # 2 vCPU 4 GB
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
  dns_prefix = "devops"
  linux_profile = {
    admin_username = "devops_admin"
    ssh_key        = azurerm_ssh_public_key.azure_aks_key.public_key
  }
  service_principal = {
    client_id     = azuread_service_principal.devops.client_id
    client_secret = azuread_service_principal_password.devops.value
  }
  local_account_disabled = false
  tags                   = var.azure_application_tags
}

module "azure_storage_account" {
  source                   = "Azure/avm-res-storage-storageaccount/azurerm"
  version                  = "0.6.4"
  location                 = var.azure_region
  name                     = "devopsprojectblob${local.env}"
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

locals {
  keyvault_private_endpoint_ip = data.azurerm_private_endpoint_connection.key_vault_private_endpoint.private_service_connection[0].private_ip_address
}

data "azurerm_private_endpoint_connection" "key_vault_private_endpoint" {
  name                = "KeyVaultPrivateEndpoint"
  resource_group_name = module.azure_resource_group.name
  depends_on          = [module.devops_key_vault]
}

module "devops_key_vault" {
  source                        = "Azure/avm-res-keyvault-vault/azurerm"
  version                       = "0.10.2"
  name                          = module.azure_naming.key_vault.name
  location                      = var.azure_region
  resource_group_name           = module.azure_resource_group.name
  sku_name                      = "premium"
  public_network_access_enabled = true # Enable for public access (with enabled firewall) but only for API calls
  network_acls = {
    bypass         = "AzureServices"
    ip_rules       = ["${data.http.user_public_ip.body}/32"] # Response body has user public IPv4 address, so we can use it to allow public access for our host.
    default_action = "Deny"                                  # For default action when no rule matches
  }
  private_endpoints = {
    aksendpoint = { # The main goal is permitting only private connection to key vault so we need to configure private endpoint
      name                          = "KeyVaultPrivateEndpoint"
      location                      = var.azure_region
      resource_group_name           = module.azure_resource_group.name
      subnet_resource_id            = module.azure_management_vnet.subnets["endpointsubnet"].resource_id
      private_dns_zone_group_name   = module.avm-res-network-private_dns_zone.name
      private_dns_zone_resource_ids = [module.avm-res-network-private_dns_zone.resource_id]
      network_interface_name        = "keyvault-${module.azure_naming.network_interface.name_unique}" # What's funny if my interface isn't assigned to any VM I cannot test connections using ICMPv4. I have been searching solution for three days.
      tags                          = var.azure_application_tags
    }
  }
  tenant_id = data.azuread_client_config.devops.tenant_id
  role_assignments = {
    useridentity = {                                  # Assign auth method to Key Vault
      role_definition_id_or_name = "Key Vault Administrator" # Using built in role on Azure - Key Vault Administrator
      principal_id               = azurerm_user_assigned_identity.devops_key_vault.principal_id
      description                = "KeyVaultUserManagedIdentity"
    }
    defaultclient = {
      role_definition_id_or_name = "Key Vault Administrator" # For default Azure client (Terraform will use it for provision Key Vault resources )
      principal_id               = data.azuread_client_config.devops.object_id
      description                = "KeyVaultDefaultClient"
    }
  }
  secrets = { # Create secret for Kubernetes external dns and cert manager
    cloudflare_api_token = {
      name = "cloudflare-api-token"
      tags = var.azure_application_tags
    }
  }
  secrets_value = {
    cloudflare_api_token = var.cloudflare_api_token
  }
  tags = var.azure_application_tags
}

module "avm-res-network-private_dns_zone" {
  source      = "Azure/avm-res-network-privatednszone/azurerm"
  version     = "0.4.3"
  domain_name = "azure.net" # Vault need to be used with TLS so the only way to establish secured connections is using HTTPS with correct domain
  parent_id   = module.azure_resource_group.resource_id
  a_records = {
    vault = { # Certificate for Vault is for vault.azure.net domain (wildcard), so that's why we can add custom subdomain
      name         = "${module.devops_key_vault.name}.vault"  # Previous version had devopsproject subdomain, but then connection with vault weren't been established properly
      ttl          = 5
      ip_addresses = [local.keyvault_private_endpoint_ip]
    }
  }
  virtual_network_links = { # Assign Private DNS Zone to VNets
    aks = {
      vnetlinkname       = "aksvnetlink"
      virtual_network_id = module.azure_node_vnet.resource_id
    }
    management = {
      vnetlinkname       = "managementvnetlink"
      virtual_network_id = module.azure_management_vnet.resource_id
    }
  }
  tags = var.azure_application_tags
}

/* KUBERNETES */ # Mainly for Key Vault and other cloud resources integration

resource "kubernetes_service_account_v1" "key_vault" { # ServiceAccount for integration with User Managed Identity which has Key Vault permissions
  metadata {
    name = "key-vault-integration"
    namespace = "external-secrets"
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.devops_key_vault.client_id
      "azure.workload.identity/tenant-id" = azurerm_user_assigned_identity.devops_key_vault.tenant_id
    }
  }
  depends_on = [kubernetes_namespace_v1.external-secrets]
}

resource "kubernetes_namespace_v1" "external-secrets" {
  metadata {
    name = "external-secrets"
  }
  depends_on = [module.azure_aks]
}

/* HELM */

resource "helm_release" "azure_workload_identity" { # Mutating Admission Webhook for Azure Workload Identity
  name       = "workload-identity-webhook"
  repository = "https://azure.github.io/azure-workload-identity/charts"
  chart      = "workload-identity-webhook"
  namespace  = "azure-workload-identity-system"
  set = [
    {
      name  = "azureTenantID"
      value = azurerm_user_assigned_identity.devops_key_vault.tenant_id
    }
  ]
  create_namespace = true
  depends_on       = [module.azure_aks]
}

# It's difficult to choose the best way to provide ArgoCD with Terraform :(
resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.0.5"
  namespace  = "argocd"
  values = [
    file(var.argocd_path_to_values) # Override default Chart values with values.yaml file located in prod/kubernetes directory
  ]
  create_namespace = true
  depends_on       = [module.azure_aks]
}

/* UTILS */

data "http" "user_public_ip" { # Using HTTP query for getting user public IPv4
  url = "https://api.ipify.org/"
  retry {
    attempts     = 5
    max_delay_ms = 1000
    min_delay_ms = 500
  }
}