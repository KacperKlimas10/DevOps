output "azure_aks_ssh_private_key" {
  value = {
    pem     = tls_private_key.azure_aks_key.private_key_pem
    openssh = tls_private_key.azure_aks_key.public_key_openssh
  }
  sensitive = true
}

output "azure_aks_kube_config" {
  value     = module.azure_aks.kube_config
  sensitive = true
}

output "azure_gha_role_client_id" {
  value = azurerm_user_assigned_identity.devops_gha_container_registry.client_id
}

output "azure_gha_role_tenant_id" {
  value = azurerm_user_assigned_identity.devops_gha_container_registry.tenant_id
}

output "azure_subscribtion_id" {
  value = var.azure_subscription_id
}