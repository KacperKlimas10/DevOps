#!/bin/bash

set -euo pipefail

ENVIRONMENT="${1:-testing}" 

cd infrastructure/terraform

./vpnsetup.sh

terraform init

if [[ $(terraform workspace list | grep "$ENVIRONMENT" | sed "s/* //") != "$ENVIRONMENT" ]]; then
    terraform workspace new $ENVIRONMENT
fi

terraform workspace select $ENVIRONMENT

terraform apply -target=module.devops_postgresql # This needs to be created first

terraform apply -auto-approve -parallelism=20

GITHUB_REPOSITORY="KacperKlimas10/DevOps"

TERRAFORM_OUTPUT=$(terraform output -json)

gh secret set AZURE_CLIENT_ID --body $(echo $TERRAFORM_OUTPUT | jq -r '.azure_gha_role_client_id.value') -R $GITHUB_REPOSITORY
gh secret set AZURE_TENANT_ID --body $(echo $TERRAFORM_OUTPUT | jq -r '.azure_gha_role_tenant_id.value') -R $GITHUB_REPOSITORY
gh secret set AZURE_SUBSCRIPTION_ID --body $(echo $TERRAFORM_OUTPUT | jq -r '.azure_subscribtion_id.value') -R $GITHUB_REPOSITORY

for microservice in user-service storage-service demo-go; do
    gh workflow run build-push.yaml \
        -R "$GITHUB_REPOSITORY"   \
        -f microservice="$microservice" \
        -f environment="$ENVIRONMENT"
done

az aks get-credentials --resource-group "rg-devopsproject_$ENVIRONMENT" --name "aks-devopsproject$ENVIRONMENT" --overwrite-existing

kubectl apply -f ../kubernetes/argocd-gitops/$ENVIRONMENT

sleep 120

kubectl rollout restart deployment -n istio-ingress istio-ingressgateway