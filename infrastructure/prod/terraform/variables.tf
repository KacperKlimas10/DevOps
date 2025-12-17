variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_dns_zone_id" {
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
  default     = "certskeys/devopsprojectCA.cer"
}