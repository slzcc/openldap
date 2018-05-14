#!/bin/bash -e

ulimit -n 1024

/usr/local/bin/initial_ldap.sh

if [ "${LDAP_TLS,,}" == "true" ]; then
	exec /usr/sbin/slapd -h "ldap://$HOSTNAME ldaps://$HOSTNAME ldapi:///" -u ldap -g ldap -d $LDAP_LOG_LEVEL
else
	exec /usr/sbin/slapd -h "ldap://$HOSTNAME ldapi:///" -u ldap -g ldap -d $LDAP_LOG_LEVEL
fi
