#!/bin/bash

source ${CONTAINER_SERVICE_DIR}/ssl/default-env

LDAP_SSL_HELPER_PREFI=$1
DEFAULT_TLS_CA_CRT_PATH=$2
DEFAULT_TLS_CA_KEY_PATH=$3
LDAP_TLS_CERT_PATH=$4

CONFIG_PARAM=${CONTAINER_SERVICE_DIR}/ssl/ca-config.json
PROFILE_PARAM=${PROFILE_PARAM:-"openldap"}
LDAP_SUB_CA_PATH=${LDAP_SUB_CA_PATH:-"/tmp/cert"}
CFSSL_CSR=${CONTAINER_SERVICE_DIR}/ssl/req-csr.json.tmpl

# set csr file
CSR_FILE="/tmp/csr-file"
if [ -n "$CFSSL_CSR_JSON" ]; then
    log-helper debug "use CFSSL_CSR_JSON value as csr file"
    echo $CFSSL_CSR_JSON > $CSR_FILE
elif [ -n "$CFSSL_CSR" ]; then
  log-helper debug "use $CFSSL_CSR as csr file"
  cp -f $CFSSL_CSR $CSR_FILE

  sed -i "s|{{ CFSSL_DEFAULT_CA_CSR_CN }}|${CFSSL_DEFAULT_CA_CSR_CN}|g" $CSR_FILE
  sed -i "s|{{ CFSSL_DEFAULT_CA_CSR_KEY_ALGO }}|${CFSSL_DEFAULT_CA_CSR_KEY_ALGO}|g" $CSR_FILE
  sed -i "s|{{ CFSSL_DEFAULT_CA_CSR_KEY_SIZE }}|${CFSSL_DEFAULT_CA_CSR_KEY_SIZE}|g" $CSR_FILE
  sed -i "s|{{ CFSSL_CERT_ORGANIZATION_UNIT }}|${CFSSL_CERT_ORGANIZATION_UNIT}|g" $CSR_FILE
  sed -i "s|{{ CFSSL_DEFAULT_CA_CSR_ORGANIZATION }}|${CFSSL_DEFAULT_CA_CSR_ORGANIZATION}|g" $CSR_FILE
  sed -i "s|{{ CFSSL_DEFAULT_CA_CSR_ORGANIZATION_UNIT }}|${CFSSL_DEFAULT_CA_CSR_ORGANIZATION_UNIT}|g" $CSR_FILE
  sed -i "s|{{ CFSSL_DEFAULT_CA_CSR_LOCATION }}|${CFSSL_DEFAULT_CA_CSR_LOCATION}|g" $CSR_FILE
  sed -i "s|{{ CFSSL_DEFAULT_CA_CSR_STATE }}|${CFSSL_DEFAULT_CA_CSR_STATE}|g" $CSR_FILE
  sed -i "s|{{ CFSSL_DEFAULT_CA_CSR_COUNTRY }}|${CFSSL_DEFAULT_CA_CSR_COUNTRY}|g" $CSR_FILE

else
  log-helper error "error: no csr file provided"
  log-helper error "CFSSL_CSR_JSON and CFSSL_CSR are empty"
  exit 1
fi

# Copy CA file
log-helper debug "Copy CA file"
ln -sf ${DEFAULT_TLS_CA_CRT_PATH} ${LDAP_TLS_CERT_PATH}/`basename ${DEFAULT_TLS_CA_CRT_PATH}`

# Generate CA
log-helper debug "Generate CA"
cfssl gencert -ca ${DEFAULT_TLS_CA_CRT_PATH} -ca-key ${DEFAULT_TLS_CA_KEY_PATH} -config ${CONFIG_PARAM} -profile ${PROFILE_PARAM} -hostname $HOSTNAME ${CSR_FILE} | cfssljson -bare ${LDAP_SUB_CA_PATH}
mv ${LDAP_SUB_CA_PATH}.pem ${LDAP_TLS_CERT_PATH}/${LDAP_SSL_HELPER_PREFI}.pem
mv ${LDAP_SUB_CA_PATH}-key.pem ${LDAP_TLS_CERT_PATH}/${LDAP_SSL_HELPER_PREFI}-key.pem

rm -rf  ${LDAP_SUB_CA_PATH}*