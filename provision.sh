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

terraform apply -auto-approve

az aks get-credentials --resource-group "rg-devopsproject_$ENVIRONMENT" --name "aks-devopsproject$ENVIRONMENT" --overwrite-existing

kubectl apply -f ../kubernetes/argocd-gitops/$ENVIRONMENT