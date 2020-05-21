#!/bin/bash

source ${CONTAINER_SERVICE_DIR}/slapd/default-env

function get_ldap_base_dn() {
  if [ -z "$LDAP_BASE_DN" ]; then
    IFS='.' read -ra LDAP_BASE_DN_TABLE <<< "$LDAP_DOMAIN"
    for i in "${LDAP_BASE_DN_TABLE[@]}"; do
      EXT="dc=$i,"
      LDAP_BASE_DN=$LDAP_BASE_DN$EXT
    done

    LDAP_BASE_DN=${LDAP_BASE_DN::-1}
    LDAP_DC=`echo $LDAP_DOMAIN | awk -F. '{print $1}'`
  fi
}

function is_new_schema() {
  local COUNT=$(ldapsearch -Q -Y EXTERNAL -H ldapi:/// -b cn=schema,cn=config cn | grep -c $1)
  if [ "$COUNT" -eq 0 ]; then
    echo 1
  else
    echo 0
  fi
}

function ldap_add_or_modify (){
  local LDIF_FILE=$1
  sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" $LDIF_FILE
  sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" $LDIF_FILE
  sed -i "s|{{ LDAP_DC }}|${LDAP_DC}|g" $LDIF_FILE
  sed -i "s|{{ LDAP_ORGANISATION }}|${LDAP_ORGANISATION}|g" $LDIF_FILE
  if [ "${LDAP_READONLY_USER,,}" == "true" ]; then
    sed -i "s|{{ LDAP_READONLY_USER_USERNAME }}|${LDAP_READONLY_USER_USERNAME}|g" $LDIF_FILE
    sed -i "s|{{ LDAP_READONLY_USER_PASSWORD_ENCRYPTED }}|${LDAP_READONLY_USER_P:ASSWORD_ENCRYPTED}|g" $LDIF_FILE
  fi
  if grep -iq "changetype: modify" $LDIF_FILE ; then
    ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f $LDIF_FILE  || ldapmodify -h localhost -p 389 -D cn=admin,$LDAP_BASE_DN -w "$LDAP_ADMIN_PASSWORD" -f $LDIF_FILE 
  else
    ldapadd -Y EXTERNAL -Q -H ldapi:/// -f $LDIF_FILE  || ldapadd -h localhost -p 389 -D cn=admin,$LDAP_BASE_DN -w "$LDAP_ADMIN_PASSWORD" -f $LDIF_FILE 
  fi
}

sleep 3

# create dir if they not already exists
[ -d /var/lib/ldap ] || mkdir -p /var/lib/ldap
[ -d /etc/openldap/slapd.d ] || mkdir -p /etc/openldap/slapd.d

# Initialize directory permissions
if [[ ! -e /etc/openldap/ldap.conf ]];then
  cp -a /opt/openldap/ldap.conf /etc/openldap/ldap.conf ;
fi

if [[ ! -e /etc/openldap/certs ]];then
  cp -a /opt/openldap/certs /etc/openldap/certs ;
fi

if [[ ! -e /etc/openldap/schema ]];then
  cp -a /opt/openldap/schema /etc/openldap/schema ;
fi

if [[ ! -e /etc/openldap/check_password.conf ]];then
  cp -a /opt/openldap/check_password.conf /etc/openldap/check_password.conf ;
fi

chown -R ldap.ldap /var/lib/ldap
chown -R ldap.ldap /etc/openldap

FIRST_START_DONE="${CONTAINER_STATE_DIR}/slapd-first-start-done"
WAS_STARTED_WITH_TLS="/etc/openldap/slapd.d/docker-openldap-was-started-with-tls"
WAS_STARTED_WITH_TLS_ENFORCE="/etc/openldap/slapd.d/docker-openldap-was-started-with-tls-enforce"
WAS_STARTED_WITH_REPLICATION="/etc/openldap/slapd.d/docker-openldap-was-started-with-replication"

LDAP_TLS_CA_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/certs/${LDAP_TLS_CA_CRT_FILENAME}"
LDAP_TLS_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/certs/${LDAP_TLS_CRT_FILENAME}"
LDAP_TLS_KEY_PATH="${CONTAINER_SERVICE_DIR}/slapd/certs/${LDAP_TLS_KEY_FILENAME}"
LDAP_TLS_DH_PARAM_PATH="${CONTAINER_SERVICE_DIR}/slapd/certs/dhparam.pem"

LDAP_SSL_HELPER_PREFIX=${LDAP_SSL_HELPER_PREFIX:-"ldap"}
DEFAULT_TLS_CA_CRT_PATH=${CONTAINER_SERVICE_DIR}/ssl/config/${LDAP_TLS_CA_CRT_FILENAME}
DEFAULT_TLS_CA_KEY_PATH=${CONTAINER_SERVICE_DIR}/ssl/config/${LDAP_TLS_CA_KEY_FILENAME}
LDAP_TLS_CERT_PATH=${CONTAINER_SERVICE_DIR}/slapd/certs

#
# Global variables
#
BOOTSTRAP=false

# Copy slapd.d for the first time
if [[ -z "$(ls -A /etc/openldap/slapd.d/)" ]] && [[ -z "$(ls -A /var/lib/ldap)" ]]; then

  BOOTSTRAP=true

  get_ldap_base_dn
  cp -a /opt/ldap/* /var/lib/ldap/
  cp -a /opt/openldap/slapd.d/* /etc/openldap/slapd.d/

    # get previous hostname if OpenLDAP was started with replication
    # to avoid configuration pbs
    PREVIOUS_HOSTNAME_PARAM=""
    if [ -e "$WAS_STARTED_WITH_REPLICATION" ]; then

      source $WAS_STARTED_WITH_REPLICATION

      # if previous hostname != current hostname
      # set previous hostname to a loopback ip in /etc/hosts
      if [ "$PREVIOUS_HOSTNAME" != "$HOSTNAME" ]; then
        echo "127.0.0.2 $PREVIOUS_HOSTNAME" >> /etc/hosts
        PREVIOUS_HOSTNAME_PARAM="ldap://$PREVIOUS_HOSTNAME"
      fi
    fi

    # if the config was bootstraped with TLS
    # to avoid error (#6) (#36) and (#44)
    # we create fake temporary certificates if they do not exists
    if [ -e "$WAS_STARTED_WITH_TLS" ]; then
      source $WAS_STARTED_WITH_TLS

      printf "Check previous TLS certificates..."

      # fix for #73
      # image started with an existing database/config created before 1.1.5
      [[ -z "$PREVIOUS_LDAP_TLS_CA_CRT_PATH" ]] && PREVIOUS_LDAP_TLS_CA_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/certs/$LDAP_TLS_CA_CRT_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_CRT_PATH" ]] && PREVIOUS_LDAP_TLS_CRT_PATH="${CONTAINER_SERVICE_DIR}/slapd/certs/$LDAP_TLS_CRT_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_KEY_PATH" ]] && PREVIOUS_LDAP_TLS_KEY_PATH="${CONTAINER_SERVICE_DIR}/slapd/certs/$LDAP_TLS_KEY_FILENAME"
      [[ -z "$PREVIOUS_LDAP_TLS_DH_PARAM_PATH" ]] && PREVIOUS_LDAP_TLS_DH_PARAM_PATH="${CONTAINER_SERVICE_DIR}/slapd/certs/dhparam.pem"

      ${CONTAINER_SERVICE_DIR}/ssl/run.sh $LDAP_SSL_HELPER_PREFIX $DEFAULT_TLS_CA_CRT_PATH $DEFAULT_TLS_CA_KEY_PATH $LDAP_TLS_CERT_PATH
      [ -f ${PREVIOUS_LDAP_TLS_DH_PARAM_PATH} ] || openssl dhparam -out ${LDAP_TLS_DH_PARAM_PATH} 2048

      chmod 600 ${PREVIOUS_LDAP_TLS_DH_PARAM_PATH}
      chown ldap:ldap $PREVIOUS_LDAP_TLS_CRT_PATH $PREVIOUS_LDAP_TLS_KEY_PATH $PREVIOUS_LDAP_TLS_CA_CRT_PATH $PREVIOUS_LDAP_TLS_DH_PARAM_PATH
    fi

    # start OpenLDAP
  nohup /usr/sbin/slapd -u ldap -g ldap -h 'ldapi:/// ldap:///' -d $LDAP_LOG_LEVEL >> /var/log/slapd.log 2>&1  &
  sleep 3

  printf "Waiting for OpenLDAP to start..."
  while [ ! -e /var/run/openldap/slapd.pid ]; do sleep 0.1; done


    if $BOOTSTRAP; then

      # base schema
    if [[ "${IMPORT_ALL_BASE_SCHEMA}" == false ]];then
      for i in ${IMPORT_BASE_SCHEMA_LIST};do
          ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f ${SCHEMA_DIR}/${i}.ldif 
      done
    else
      for i in `ls ${SCHEMA_DIR}|egrep "*\.ldif"`; do
          ldapadd -Y EXTERNAL -H ldapi:/// -D "cn=config" -f ${SCHEMA_DIR}/${i} 
      done
    fi

    # add converted schemas
    for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/schema -name \*.ldif -type f|sort); do
      log-helper debug "Processing file ${f}"
      # add schema if not already exists
      SCHEMA=$(basename "${f}" .ldif)
      ADD_SCHEMA=$(is_new_schema $SCHEMA)
      if [ "$ADD_SCHEMA" -eq 1 ]; then
        ldapadd -c -Y EXTERNAL -Q -H ldapi:/// -f $f 2>&1 | log-helper debug
      else
        log-helper info "schema ${f} already exists"
      fi
    done
    
    LDAP_ADMIN_PASSWORD_ENCRYPTED=$(slappasswd -s "$LDAP_ADMIN_PASSWORD")
    LDAP_CONFIG_PASSWORD_ENCRYPTED=$(slappasswd -s "$LDAP_CONFIG_PASSWORD")
    sed -i "s|{{ LDAP_ADMIN_PASSWORD_ENCRYPTED }}|${LDAP_ADMIN_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/ldif/01-config-password.ldif
    sed -i "s|{{ LDAP_CONFIG_PASSWORD_ENCRYPTED }}|${LDAP_CONFIG_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/ldif/01-config-password.ldif
    sed -i "s|{{ LDAP_CONFIG_PASSWORD_ENCRYPTED }}|${LDAP_CONFIG_PASSWORD_ENCRYPTED}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/ldif/04-baseTree.ldif

    sed -i "s|{{ LDAP_BASE_DN }}|${LDAP_BASE_DN}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/ldif/02-security.ldif

    printf "Add image bootstrap ldif..."
    for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/ldif -mindepth 1 -maxdepth 1 -type f -name \*.ldif  | sort); do
      ldap_add_or_modify "$f"
    done

    # read only user
    if [ "${LDAP_READONLY_USER,,}" == "true" ]; then
      printf "Add read only user..."

      LDAP_READONLY_USER_PASSWORD_ENCRYPTED=$(slappasswd -s $LDAP_READONLY_USER_PASSWORD)

      ldap_add_or_modify "${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/ldif/readonly-user/readonly-user.ldif"
      ldap_add_or_modify "${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/ldif/readonly-user/readonly-user-acl.ldif"
    fi

    printf "Add custom bootstrap ldif..."
    for f in $(find ${CONTAINER_SERVICE_DIR}/slapd/config/bootstrap/ldif/custom -type f -name \*.ldif  | sort); do
      ldap_add_or_modify "$f"
    done

    fi


    #
    # TLS config
    #
    if [ -e "$WAS_STARTED_WITH_TLS" ] && [ "${LDAP_TLS,,}" != "true" ]; then
      printf "/!\ WARNING: LDAP_TLS=false but the container was previously started with LDAP_TLS=true"
      printf "TLS can't be disabled once added. Ignoring LDAP_TLS=false."
      LDAP_TLS=true
    fi

    if [ -e "$WAS_STARTED_WITH_TLS_ENFORCE" ] && [ "${LDAP_TLS_ENFORCE,,}" != "true" ]; then
      printf "/!\ WARNING: LDAP_TLS_ENFORCE=false but the container was previously started with LDAP_TLS_ENFORCE=true"
      printf "TLS enforcing can't be disabled once added. Ignoring LDAP_TLS_ENFORCE=false."
      LDAP_TLS_ENFORCE=true
    fi

    if [ "${LDAP_TLS,,}" == "true" ]; then

      printf "Add TLS config..."

      ${CONTAINER_SERVICE_DIR}/ssl/run.sh $LDAP_SSL_HELPER_PREFIX $DEFAULT_TLS_CA_CRT_PATH $DEFAULT_TLS_CA_KEY_PATH $LDAP_TLS_CERT_PATH

      # create DHParamFile if not found
      [ -f ${LDAP_TLS_DH_PARAM_PATH} ] || openssl dhparam -out ${LDAP_TLS_DH_PARAM_PATH} 2048
      chmod 600 ${LDAP_TLS_DH_PARAM_PATH}

      # fix file permissions
      chown -R ldap:ldap ${CONTAINER_SERVICE_DIR}/slapd

      # adapt tls ldif
      sed -i "s|{{ LDAP_TLS_CA_CRT_PATH }}|${LDAP_TLS_CA_CRT_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_CRT_PATH }}|${LDAP_TLS_CRT_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_KEY_PATH }}|${LDAP_TLS_KEY_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_DH_PARAM_PATH }}|${LDAP_TLS_DH_PARAM_PATH}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/tls/tls-enable.ldif

      sed -i "s|{{ LDAP_TLS_CIPHER_SUITE }}|${LDAP_TLS_CIPHER_SUITE}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/tls/tls-enable.ldif
      sed -i "s|{{ LDAP_TLS_VERIFY_CLIENT }}|${LDAP_TLS_VERIFY_CLIENT}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/tls/tls-enable.ldif

      ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/config/tls/tls-enable.ldif 

      [[ -f "$WAS_STARTED_WITH_TLS" ]] && rm -f "$WAS_STARTED_WITH_TLS"
      echo "export PREVIOUS_LDAP_TLS_CA_CRT_PATH=${LDAP_TLS_CA_CRT_PATH}" > $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_CRT_PATH=${LDAP_TLS_CRT_PATH}" >> $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_KEY_PATH=${LDAP_TLS_KEY_PATH}" >> $WAS_STARTED_WITH_TLS
      echo "export PREVIOUS_LDAP_TLS_DH_PARAM_PATH=${LDAP_TLS_DH_PARAM_PATH}" >> $WAS_STARTED_WITH_TLS

      # enforce TLS
      if [ "${LDAP_TLS_ENFORCE,,}" == "true" ]; then
        printf "Add enforce TLS..."
        ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/config/tls/tls-enforce-enable.ldif 
        touch $WAS_STARTED_WITH_TLS_ENFORCE
      fi
    fi


    #
    # Replication config
    #
    function disableReplication() {
      sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-disable.ldif
      ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-disable.ldif  || true
      [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
    }

    if [ "${LDAP_REPLICATION,,}" == "true" ]; then

      printf "Add replication config..."

      i=1

      if [ "LDAP_REPLICATION_TYPE" == "Multi" ];then
        for host in `echo $LDAP_REPLICATION_HOSTS`;do
          if [[ $( basename ${host}) == $HOSTNAME ]];then
            sed -i "s|{{ LDAP_REPLICATION_HOSTS }}|olcServerID: $i ${host}\n{{ LDAP_REPLICATION_HOSTS }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
            sed -i "s|{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|olcSyncRepl: rid=00$i provider=${host} ${LDAP_REPLICATION_CONFIG_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
            sed -i "s|{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|olcSyncRepl: rid=10$i provider=${host} ${LDAP_REPLICATION_DB_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
          else
            sed -i "s|{{ LDAP_REPLICATION_HOSTS }}|olcServerID: $i ${host}\n{{ LDAP_REPLICATION_HOSTS }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
            sed -i "s|{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|olcSyncRepl: rid=00$i provider=${host} ${LDAP_REPLICATION_CONFIG_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
            sed -i "s|{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|olcSyncRepl: rid=10$i provider=${host} ${LDAP_REPLICATION_DB_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
          fi
            ((i++))
        done

        sed -i "s|\$LDAP_BASE_DN|$LDAP_BASE_DN|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
        sed -i "s|\$LDAP_ADMIN_PASSWORD|$LDAP_ADMIN_PASSWORD|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
        sed -i "s|\$LDAP_CONFIG_PASSWORD|$LDAP_CONFIG_PASSWORD|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif

        sed -i "/{{ LDAP_REPLICATION_HOSTS }}/d" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
        sed -i "/{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}/d" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
        sed -i "/{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}/d" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif

        sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif

        ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif  || true

        [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"

      elif [ "LDAP_REPLICATION_TYPE" == "Syncrepl" ];then
        for host in `echo $LDAP_REPLICATION_HOSTS`;do
          if [[ $( basename ${host}) == $HOSTNAME ]];then
            sed -i "s|{{ LDAP_REPLICATION_HOSTS }}|olcServerID: $i ${host}\n{{ LDAP_REPLICATION_HOSTS }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
            sed -i "s|{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|olcSyncRepl: rid=00$i provider=${host} ${LDAP_REPLICATION_CONFIG_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
            sed -i "s|{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|olcSyncRepl: rid=10$i provider=${host} ${LDAP_REPLICATION_DB_SYNCPROV}\n{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable.ldif
          fi
            ((i++))
        done

        sed -i "s|\$LDAP_BASE_DN|$LDAP_BASE_DN|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable-syncrepl.ldif
        sed -i "s|\$LDAP_ADMIN_PASSWORD|$LDAP_ADMIN_PASSWORD|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable-syncrepl.ldif
        sed -i "s|\$LDAP_CONFIG_PASSWORD|$LDAP_CONFIG_PASSWORD|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable-syncrepl.ldif

        sed -i "/{{ LDAP_REPLICATION_HOSTS }}/d" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable-syncrepl.ldif
        sed -i "/{{ LDAP_REPLICATION_HOSTS_CONFIG_SYNC_REPL }}/d" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable-syncrepl.ldif
        sed -i "/{{ LDAP_REPLICATION_HOSTS_DB_SYNC_REPL }}/d" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable-syncrepl.ldif

        sed -i "s|{{ LDAP_BACKEND }}|${LDAP_BACKEND}|g" ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable-syncrepl.ldif

        ldapmodify -c -Y EXTERNAL -Q -H ldapi:/// -f ${CONTAINER_SERVICE_DIR}/slapd/config/replication/replication-enable-syncrepl.ldif  || true

        [[ -f "$WAS_STARTED_WITH_REPLICATION" ]] && rm -f "$WAS_STARTED_WITH_REPLICATION"
        
      fi

      echo "export PREVIOUS_HOSTNAME=${HOSTNAME}" > $WAS_STARTED_WITH_REPLICATION

  else

      printf "Disable replication config..."
      disableReplication || true

    fi

    #
    # stop OpenLDAP
    #
    printf "Stop OpenLDAP..."

    SLAPD_PID=$(cat /var/run/openldap/slapd.pid)
    kill -15 $SLAPD_PID
    while [ -e /proc/$SLAPD_PID ]; do sleep 0.1; done # wait until slapd is terminated
fi

#
# ldap client config
#
get_ldap_base_dn
if [ "${LDAP_TLS,,}" == "true" ]; then
  log-helper info "Configure ldap client TLS configuration..."
  sed -i '$d' /etc/openldap/ldap.conf
  sed -i --follow-symlinks "s,TLS_CACERT.*,TLS_CACERT ${LDAP_TLS_CA_CRT_PATH},g" /etc/openldap/ldap.conf
  echo "TLS_CACERT ${LDAP_TLS_CA_CRT_PATH}" >> /etc/openldap/ldap.conf
  echo "TLS_REQCERT ${LDAP_TLS_VERIFY_CLIENT}" >> /etc/openldap/ldap.conf
  echo "BASE   $LDAP_BASE_DN" >> /etc/openldap/ldap.conf
  echo "URI    ldaps://$HOSTNAME" >> /etc/openldap/ldap.conf
  cp -f /etc/openldap/ldap.conf ${CONTAINER_SERVICE_DIR}/slapd/ldap.conf

  [[ -f "$HOME/.ldaprc" ]] && rm -f $HOME/.ldaprc
  echo "TLS_CERT ${LDAP_TLS_CRT_PATH}" > $HOME/.ldaprc
  echo "TLS_KEY ${LDAP_TLS_KEY_PATH}" >> $HOME/.ldaprc
  cp -f $HOME/.ldaprc ${CONTAINER_SERVICE_DIR}/slapd/.ldaprc
else
  echo "BASE   $LDAP_BASE_DN" >> /etc/openldap/ldap.conf
  echo "URI    ldap://$HOSTNAME" >> /etc/openldap/ldap.conf
fi


if [ "${LDAP_REMOVE_CONFIG_AFTER_SETUP,,}" == "true" ]; then
  printf "Remove config files..."
  rm -rf ${CONTAINER_SERVICE_DIR}/slapd/config
fi
