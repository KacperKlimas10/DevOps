#!/bin/bash

CA_KEY_NAME="devopsCAkey.pem"
CA_CERT_PEM_NAME="devopsCA.pem"
CA_CERT_CER_NAME="devopsCA.cer"

CLIENT_KEY_NAME="clientkey.pem"
CLIENT_REQ_NAME="clientreq.pem"
CLIENT_CERT_NAME="clientcert.pem"

DIRECTORY="certskeys"

function generateRootCert {
 openssl genrsa -out $CA_KEY_NAME 2048 && \
 openssl req -x509 -new -nodes -key $CA_KEY_NAME \
  -subj "/CN=VPN CA" -days 3650 -out $CA_CERT_PEM_NAME && \
 openssl x509 -in $CA_CERT_PEM_NAME -outform der | base64 -w0 | xargs echo > $CA_CERT_CER_NAME
}

function generateClientCert {
 openssl genrsa -out $CLIENT_KEY_NAME 2048 && \
 openssl req -new -key $CLIENT_KEY_NAME -out $CLIENT_REQ_NAME -subj "/CN=DevOpsProjectClient" && \
 openssl x509 -req -days 365 -in $CLIENT_REQ_NAME -CA $CA_CERT_PEM_NAME -CAkey $CA_KEY_NAME \
  -CAcreateserial -out $CLIENT_CERT_NAME -extfile <(echo -e "subjectAltName=DNS:$(hostname)\nextendedKeyUsage=clientAuth")
}

if [ ! -d "$DIRECTORY" ]; then
 mkdir $DIRECTORY
 sleep 1
 cd $DIRECTORY && generateRootCert && generateClientCert && rm $CLIENT_REQ_NAME
 echo "CERTS CREATED AT $(pwd)"
fi
exit 0