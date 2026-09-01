/* CLOUDFLARE */

# R2 OBJECT STORAGE
resource "cloudflare_r2_bucket" "devops_r2_bucket" {
  account_id    = var.cloudflare_account_id
  name          = "devopsproject-r2-${local.env}"
  location      = "EEUR"
  storage_class = "Standard"
}

resource "cloudflare_r2_custom_domain" "devops_r2_custom_domain" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.devops_r2_bucket.name
  domain      = "r2storage-${local.env}.kacperklimas.com"
  enabled     = true
  zone_id     = var.cloudflare_dns_zone_id
  min_tls     = "1.2" # What's interesting R2 resource block use TLS 1.0 as default minimum version which is not recommended and can cause major security issues, so we need to change to TLS 1.2
}

/* AZURE */

locals {
  env                      = var.azure_application_tags.env
  azure_resourcegroup_name = module.azure_naming.resource_group.name
}

# Azure Identity for Kubernetes Cluster

resource "azurerm_user_assigned_identity" "aks_cluster" {
  name                = "aks-identity-${local.env}"
  resource_group_name = module.azure_resource_group.name
  location            = var.azure_region
  tags                = var.azure_application_tags
}

resource "azurerm_role_assignment" "aks_cluster_network" {
  scope                = module.azure_resource_group.resource_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_cluster.principal_id
}

data "azuread_client_config" "devops" {} # Data about default Azure user

# Azure Identity for Azure Key Vault

resource "azurerm_user_assigned_identity" "devops_key_vault" {
  name                = "keyvault_uai"
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

# Azure Identity for Azure Container Registry (GitHub Actions CI pipeline)

resource "azurerm_user_assigned_identity" "devops_gha_container_registry" {
  name                = "gha_containerregistry_uai"
  resource_group_name = module.azure_resource_group.name
  location            = var.azure_region
  tags                = var.azure_application_tags
}

resource "azurerm_federated_identity_credential" "devops_gha_container_registry" {
  name                = "github-actions-federated-credential"
  parent_id           = azurerm_user_assigned_identity.devops_gha_container_registry.id
  resource_group_name = module.azure_resource_group.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com" # OIDC Issuer from GitHub Actions
  subject             = var.github_actions_oidc_subject               # Default: repo:KacperKlimas10/DevOps:ref:refs/heads/master
}

# Azure Identity for Azure Container Registry (Kubernetes)

resource "azurerm_user_assigned_identity" "devops_kubernetes_container_registry" {
  name                = "k8s_containerregistry_uai"
  resource_group_name = module.azure_resource_group.name
  location            = var.azure_region
  tags                = var.azure_application_tags
}

resource "azurerm_federated_identity_credential" "devops_kubernetes_container_registry" {
  name                = "kubernetes-federated-credential"
  parent_id           = azurerm_user_assigned_identity.devops_kubernetes_container_registry.id
  resource_group_name = module.azure_resource_group.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.azure_aks.oidc_issuer_url # OIDC Issuer from Kubernetes Cluster
  subject             = "system:serviceaccount:external-secrets:acr-integration"
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

# Azure VPN Gateway
resource "azurerm_virtual_network_gateway" "vpn_gateway" {
  name                = module.azure_naming.virtual_network_gateway.name_unique
  location            = var.azure_region
  resource_group_name = module.azure_resource_group.name
  type                = "Vpn"
  generation          = "Generation1"
  sku                 = "VpnGw1AZ" # Zone-redundant gateway -> VpnGw2AZ
  ip_configuration {
    public_ip_address_id = azurerm_public_ip.vpn_public_ip.id
    subnet_id            = module.azure_management_vnet.subnets["vpnsubnet"].resource_id
  }
  vpn_client_configuration {
    vpn_auth_types       = ["Certificate"]
    vpn_client_protocols = ["IkeV2", "OpenVPN"]
    address_space        = ["172.16.0.0/24"]
    root_certificate {
      name             = "devopsCA" # Azure documentation says if we want to use self generated certificate we need to take part without --BEGIN CERTIFICATE-- and --END CERTIFICATE-- lines, so we use regular expressions to do that.
      public_cert_data = replace(file(var.azure_vpn_path_to_cert), "/-.*-/", "")
    }
  }
  tags = var.azure_application_tags
}

# Azure Virtual Networks
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
  name          = "vnet-devops-aks"
  parent_id     = module.azure_resource_group.resource_id
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
  depends_on                = [azurerm_virtual_network_gateway.vpn_gateway]
}

# Azure Network Security Groups
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

# Azure Managed Kubernetes Cluster
module "azure_aks" {
  source                    = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version                   = "0.3.0"
  location                  = var.azure_region
  name                      = "${module.azure_naming.kubernetes_cluster.name}${local.env}"
  resource_group_name       = module.azure_resource_group.name
  node_resource_group_name  = "rg_devopsproject_node_${local.env}"
  sku_tier                  = "Standard"
  workload_identity_enabled = true # Enable Workload Identity for Key Vault. In this case we don't have to install it manually via Helm
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
  # node_pools = {
  #   "node1" = { # User Node VirtualMachineScaleSets
  #     name                 = "usrnode1"
  #     vm_size              = "Standard_D2ds_v4" # 2 vCPU 4 GB
  #     os_sku               = "AzureLinux"
  #     auto_scaling_enabled = true
  #     min_count            = 1
  #     node_count           = 1
  #     max_count            = 3
  #     vnet_subnet_id       = module.azure_node_vnet.subnets["subnet2"].resource_id
  #     zones                = ["1", "2", "3"] # All Availability Zones
  #     tags                 = var.azure_application_tags
  #   }
  #   "node2" = { # User Node VirtualMachineScaleSets
  #     name                 = "usrnode2"
  #     vm_size              = "Standard_D2ds_v4" # 2 vCPU 4 GB
  #     os_sku               = "AzureLinux"
  #     auto_scaling_enabled = true
  #     min_count            = 1
  #     node_count           = 1
  #     max_count            = 3
  #     vnet_subnet_id       = module.azure_node_vnet.subnets["subnet3"].resource_id
  #     zones                = ["1", "2", "3"] # All Availability Zones
  #     tags                 = var.azure_application_tags
  #   }
  # }
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
    admin_username = "devops${local.env}_admin"
    ssh_key        = azurerm_ssh_public_key.azure_aks_key.public_key
  }
  managed_identities = {
    system_assigned            = false
    user_assigned_resource_ids = [azurerm_user_assigned_identity.aks_cluster.id]
  }
  local_account_disabled = false
  tags                   = var.azure_application_tags
}

locals { # Local variable to pass in ACR config and Secret config
  aks_acr_token = "aks-token"
}

# Azure Container Registry
module "azure_container_registry" {
  source                        = "Azure/avm-res-containerregistry-registry/azurerm"
  version                       = "0.5.0"
  location                      = var.azure_region
  name                          = "${module.azure_naming.container_registry.name}${local.env}"
  resource_group_name           = module.azure_resource_group.name
  sku                           = "Premium"
  zone_redundancy_enabled       = true
  public_network_access_enabled = true
  role_assignments = {
    github_identity = {                      # Assign auth method to Container Registry
      role_definition_id_or_name = "AcrPush" # Using built in role on Azure for pushing images
      principal_id               = azurerm_user_assigned_identity.devops_gha_container_registry.principal_id
      description                = "ACRUserManagedIdentity - GitHub Actions CI pipeline"
    }
    kubernetes_identity = {
      role_definition_id_or_name = "AcrPull" # Using built in role on Azure for pulling images
      principal_id               = azurerm_user_assigned_identity.devops_kubernetes_container_registry.principal_id
      description                = "ACRUserManagedIdentity - Kubernetes"
    }
  }
  scope_maps = { # Here we are setting access authentication to ACR
    aksscope = {
      name        = "aks-scope" # Authorization read only (Pulling images, reading statuses etc)
      actions     = ["repositories/*/content/read", "repositories/*/metadata/read"]
      description = "Read-only all repositories"
      registry_tokens = {
        akstoken = {
          name = local.aks_acr_token
          passwords = {
            password1 = { # Expiration date for token password
              expiry = "2026-12-31T00:00:00Z"
            }
          }
        }
      }
    }
  }
  private_endpoints = {
    aksendpoint = { # The main goal is permitting only private connection to Container Registry so we need to configure private endpoint
      name                          = "ContainerRegistryPrivateEndpoint"
      location                      = var.azure_region
      resource_group_name           = module.azure_resource_group.name
      subnet_resource_id            = module.azure_management_vnet.subnets["endpointsubnet"].resource_id
      private_dns_zone_group_name   = module.devops_container_registry_private_dns_zone.name
      private_dns_zone_resource_ids = [module.devops_container_registry_private_dns_zone.resource_id]
      network_interface_name        = "containerregistry-${module.azure_naming.network_interface.name}${local.env}" # What's funny if my interface isn't assigned to any VM I cannot test connections using ICMPv4. I have been searching solution for three days.
      tags                          = var.azure_application_tags
    }
  }
  tags = var.azure_application_tags
}

data "azurerm_container_registry" "azure_container_registry" {
  name                = module.azure_container_registry.name
  resource_group_name = module.azure_resource_group.name
  depends_on          = [module.azure_container_registry]
}

locals {
  keyvault_private_endpoint_ip    = data.azurerm_private_endpoint_connection.key_vault_private_endpoint.private_service_connection[0].private_ip_address
  container_registry_aks_password = module.azure_container_registry.scope_maps["aksscope"].registry_token_passwords["akstoken"].password1[0].value
}

# Azure Key Vault
module "devops_key_vault" {
  source                        = "Azure/avm-res-keyvault-vault/azurerm"
  version                       = "0.10.2"
  name                          = "${module.azure_naming.key_vault.name}-${local.env}"
  location                      = var.azure_region
  resource_group_name           = module.azure_resource_group.name
  sku_name                      = "premium"
  purge_protection_enabled      = false # That option optimizes Key Vault for IaC provisioning, but then we can't restore that Key Vault
  public_network_access_enabled = true  # Enable for public access (with enabled firewall) but only for API calls
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
      private_dns_zone_group_name   = module.devops_key_vault_private_dns_zone.name
      private_dns_zone_resource_ids = [module.devops_key_vault_private_dns_zone.resource_id]
      network_interface_name        = "keyvault-${module.azure_naming.network_interface.name}${local.env}" # What's funny if my interface isn't assigned to any VM I cannot test connections using ICMPv4. I have been searching solution for three days.
      tags                          = var.azure_application_tags
    }
  }
  tenant_id = data.azuread_client_config.devops.tenant_id
  role_assignments = {
    kubernetesidentity = {                                  # Assign auth method to Key Vault
      role_definition_id_or_name = "Key Vault Secrets User" # Using built in role on Azure - Key Vault User (Read only) The Principle of Least Privilege
      principal_id               = azurerm_user_assigned_identity.devops_key_vault.principal_id
      description                = "KeyVaultUserManagedIdentity"
    }
    defaultclient = {
      role_definition_id_or_name = "Key Vault Administrator" # For default Azure client (Terraform will use it for provision Key Vault resources )
      principal_id               = data.azuread_client_config.devops.object_id
      description                = "KeyVaultDefaultClient"
    }
  }
  secrets = { # Create secret for Kubernetes external dns and cert manager whole workload
    cloudflare_r2_api_uri = {
      name = "cloudflare-r2-api-uri"
      tags = var.azure_application_tags
    }
    cloudflare_r2_account_id = {
      name = "cloudflare-r2-account-id"
      tags = var.azure_application_tags
    }
    cloudflare_api_token = {
      name = "cloudflare-api-token"
      tags = var.azure_application_tags
    }
    acr_name = {
      name = "acr-name"
      tags = var.azure_application_tags
    }
    aks_registry_token = {
      name = "aks-acr-token"
      tags = var.azure_application_tags
    }
    aks_registry_password = {
      name = "aks-acr-password"
      tags = var.azure_application_tags
    }
    postgresql_uri = {
      name = "postgresql-uri"
      tags = var.azure_application_tags
    }
    postgresql_username = {
      name = "postgresql-username"
      tags = var.azure_application_tags
    }
    postgresql_password = {
      name = "postgresql-password"
      tags = var.azure_application_tags
    }
  }
  secrets_value = {
    cloudflare_r2_api_uri    = "https://${cloudflare_r2_custom_domain.devops_r2_custom_domain.domain}/${cloudflare_r2_bucket.devops_r2_bucket.name}"
    cloudflare_r2_account_id = var.cloudflare_account_id
    cloudflare_api_token     = var.cloudflare_api_token
    acr_name                 = module.azure_container_registry.name
    aks_registry_token       = local.aks_acr_token # Here we need to pass ACR token name
    aks_registry_password    = local.container_registry_aks_password
    postgresql_uri           = data.azurerm_postgresql_flexible_server.devops_postgresql.fqdn
    postgresql_username      = data.azurerm_postgresql_flexible_server.devops_postgresql.administrator_login
    postgresql_password      = random_password.postgresql_admin_password.result
  }
  tags = var.azure_application_tags
}

# Azure Postgresql Database
module "devops_postgresql" {
  source              = "Azure/avm-res-dbforpostgresql-flexibleserver/azurerm"
  version             = "0.1.4"
  name                = "${module.azure_naming.postgresql_server.name}-${local.env}"
  resource_group_name = module.azure_resource_group.name
  location            = var.azure_region
  server_version      = "16"                  # Postgresql 16
  sku_name            = "GP_Standard_D2ds_v4" # 2 vCores, 8 GiB memory, 3750 max iops for Server VM. Depends on Region and current availability
  storage_mb          = "32768"               # 32 GB on SSD Disk
  authentication = {
    password_auth_enabled         = true
    active_directory_auth_enabled = true
    tenant_id                     = data.azuread_client_config.devops.tenant_id
  }
  administrator_login    = "postgresqluser${local.env}" # Setting admin credentials that will be stored in Key Vault and synced with Kubernetes
  administrator_password = random_password.postgresql_admin_password.result
  high_availability = {
    mode = "SameZone"   # To make infrastructure faster
  }
  zone = "1" # Need to choose AZ for correct provisioning
  databases = {
    devops = {
      name = "devops"
    }
  }
  public_network_access_enabled = false
  private_endpoints = {
    aksendpoint = {
      name                          = "PostgresqlPrivateEndpoint"
      location                      = var.azure_region
      resource_group_name           = module.azure_resource_group.name
      subnet_resource_id            = module.azure_management_vnet.subnets["endpointsubnet"].resource_id
      private_dns_zone_group_name   = module.devops_postgresql_private_dns_zone.name
      private_dns_zone_resource_ids = [module.devops_postgresql_private_dns_zone.resource_id]
      network_interface_name        = "postgresql-${module.azure_naming.network_interface.name}${local.env}"
      tags                          = var.azure_application_tags
    }
  }
  tags = var.azure_application_tags
}

# In  this section we need to retrieve IPv4 addresses from Private Endpoint configurations
data "azurerm_postgresql_flexible_server" "devops_postgresql" {
  name                = module.devops_postgresql.name
  resource_group_name = module.azure_resource_group.name
  depends_on          = [module.devops_postgresql]
}

data "azurerm_private_endpoint_connection" "key_vault_private_endpoint" {
  name                = "KeyVaultPrivateEndpoint"
  resource_group_name = module.azure_resource_group.name
  depends_on          = [module.devops_key_vault]
}

# Private DNS Zones (These are very important because we can use TLS protocol in isolated private Azure network without exposing endpoints outside. Azure usually provides TLS wildcard certs that we can use with resource name as subdomain)
module "devops_key_vault_private_dns_zone" {
  source      = "Azure/avm-res-network-privatednszone/azurerm"
  version     = "0.4.3"
  domain_name = "azure.net" # Vault need to be used with TLS so the only way to establish secured connections is using HTTPS with correct domain
  parent_id   = module.azure_resource_group.resource_id
  a_records = {
    vault = {                                                # Certificate for Vault is for vault.azure.net domain (wildcard), so that's why we can add custom subdomain
      name         = "${module.devops_key_vault.name}.vault" # Previous version had devopsproject subdomain, but then connection with vault weren't been established properly
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

module "devops_container_registry_private_dns_zone" {
  source      = "Azure/avm-res-network-privatednszone/azurerm"
  version     = "0.4.3"
  domain_name = "azurecr.io"
  parent_id   = module.azure_resource_group.resource_id
  # a_records = { # I don't know why ACR module enter primary (data) Private DNS record automatically, I had some bugs with that because methods used in other resources (DB, Key Vault) are using one IPv4 address and one domain per resource. I couldn't pull images from registry because DNS records weren't configured correctly
  #   acr_io = {
  #     name         = module.azure_container_registry.name
  #     ttl          = 5
  #     ip_addresses = [local.container_registry_main_endpoint_ip]
  #   }
  # }
  virtual_network_links = {
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

module "devops_postgresql_private_dns_zone" {
  source      = "Azure/avm-res-network-privatednszone/azurerm"
  version     = "0.4.3"
  domain_name = "postgres.database.azure.com"
  parent_id   = module.azure_resource_group.resource_id
  # a_records = { # Same problem as with ACR
  #   db = {
  #     name         = module.devops_postgresql.name
  #     ttl          = 5
  #     ip_addresses = [local.postgresql_private_endpoint_ip]
  #   }
  # }
  virtual_network_links = {
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

resource "kubernetes_namespace_v1" "external-secrets" {
  metadata {
    name = "external-secrets"
  }
  depends_on = [module.azure_aks]
}

resource "kubernetes_service_account_v1" "key_vault" { # ServiceAccount for integration with User Managed Identity which has Key Vault permissions
  metadata {
    name      = "key-vault-integration"
    namespace = "external-secrets"
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.devops_key_vault.client_id
      "azure.workload.identity/tenant-id" = azurerm_user_assigned_identity.devops_key_vault.tenant_id
    }
  }
  depends_on = [kubernetes_namespace_v1.external-secrets]
}

resource "kubernetes_service_account_v1" "container_registry" { # ServiceAccount for integration with User Managed Identity which has Container Registry permissions
  metadata {
    name      = "acr-integration"
    namespace = "external-secrets"
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.devops_kubernetes_container_registry.client_id
      "azure.workload.identity/tenant-id" = azurerm_user_assigned_identity.devops_kubernetes_container_registry.tenant_id
    }
  }
  depends_on = [kubernetes_namespace_v1.external-secrets]
}

/* HELM */

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

# Random password for Azure Postgresql Admin account
resource "random_password" "postgresql_admin_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}