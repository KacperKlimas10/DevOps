variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_dns_zone_id" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
}

variable "azure_application_suffix" {
  type    = list(string)
  default = ["devopsproject"]
}

variable "azure_application_tags" {
  type = map(any)
  default = {
    "appname" : "devopsproject"
    "env" : "prod"
  }
}

variable "azure_region" {
  type    = string
  default = "eastus2"
}

variable "azure_subscription_id" {
  type = string
}

variable "azure_vpn_path_to_cert" {
  type        = string
  description = "Path to generated DER .CER CA certificate"
  default     = "certskeys/devopsCA.cer"
}

variable "argocd_path_to_values" {
  type        = string
  description = "Path to ArgoCD Helm values.yaml"
  default     = "../kubernetes/helm-values/argocd/values-production.yaml"
}

variable "github_actions_oidc_subject" {
  type        = string
  description = "GitHub Actions subject pointing at your organization's repository"
  default     = "repo:KacperKlimas10/DevOps"
}