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