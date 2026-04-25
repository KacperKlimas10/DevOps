cloudflare_account_id  = "your-clouflare-account-id"
cloudflare_api_token   = "your-cloudflare-api-token"
cloudflare_dns_zone_id = "your-cloudflare-dns-zone-id"

azure_subscription_id = "your-azure-subscription-id"
azure_region          = "polandcentral"

github_actions_oidc_subject = "repo:organization/repository"

argocd_path_to_values = "../kubernetes/infrastructure/helm/staging/argocd/values.yaml"

azure_application_tags = {
  "appname" : "foobazz"
  "env" : "stag"
}