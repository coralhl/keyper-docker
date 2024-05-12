#!/bin/bash -e
#############################################################################
#                       Confidentiality Information                         #
#                                                                           #
# This module is the confidential and proprietary information of            #
# DBSentry Corp.; it is not to be copied, reproduced, or transmitted in any #
# form, by any means, in whole or in part, nor is it to be used for any     #
# purpose other than that for which it is expressly provided without the    #
# written permission of DBSentry Corp.                                      #
#                                                                           #
# Copyright (c) 2020-2021 DBSentry Corp.  All Rights Reserved.              #
#                                                                           #
#############################################################################
log-helper level eq trace && set -x

ulimit ${LDAP_NOFILE}

log-helper info "Setting UID/GID for nginx to ${NGINX_UID}/${NGINX_GID}"
[ "$(id -g nginx)" -eq ${NGINX_GID} ] || groupmod -g ${NGINX_GID} ldap
[ "$(id -u nginx)" -eq ${NGINX_UID} ] || usermod -u ${NGINX_UID} -g ${NGINX_GID} ldap

[ -d /etc/ldap/slapd.d ] || mkdir /etc/ldap/slapd.d
[ -d /etc/ldap/tls ] || mkdir /etc/ldap/tls
[ -d /run/slapd ] || mkdir /run/slapd
[ -d /var/log/ldap ] || mkdir /var/log/ldap

ulimit ${LDAP_NOFILE}

[ -z ${LDAP_ADMIN_PASSWORD} ] || PASS=${LDAP_ADMIN_PASSWORD} 
[ -z ${LDAP_DOMAIN} ] || DOMAIN=${LDAP_DOMAIN} 
[ -z "${LDAP_ORGANIZATION_NAME}" ] || ORG_NAME=${LDAP_ORGANIZATION_NAME} 

export BASEDN="dc=`echo ${DOMAIN} | sed 's/\./,dc=/g'`"

log-helper info '--------------------------------------------------'
log-helper info 'OpenLDAP database configuration'
log-helper info '--------------------------------------------------'
log-helper info "LDAP ORG:     ${ORG_NAME}"
log-helper info "LDAP DOMAIN:  ${DOMAIN}"
log-helper info "ADMIN PASSWD: ${PASS}"
log-helper info "BASEDN:       ${BASEDN}"
log-helper info '--------------------------------------------------'

cp /etc/nginx/certs/* /etc/ldap/tls

LDAP_TLS_CA_CRT_PATH=/etc/ldap/tls/$LDAP_TLS_CA_CRT_FILENAME
LDAP_TLS_CRT_PATH=/etc/ldap/tls/$LDAP_TLS_CRT_FILENAME
LDAP_TLS_KEY_PATH=/etc/ldap/tls/$LDAP_TLS_KEY_FILENAME
LDAP_TLS_DH_PARAM_PATH=/etc/ldap/tls/$LDAP_TLS_DH_PARAM_FILENAME

FIRST_START_DONE="${CONTAINER_STATE_DIR}/openldap-first-start-done"

if [ ! -e "$FIRST_START_DONE" ]; then
	BOOTSTRAP=false

	if [ -z "$(ls -A /var/lib/ldap | grep -v lost+found)" ] &&     \
	   [ -z "$(ls -A /etc/ldap/slapd.d | grep -v lost+found)" ]; then
		BOOTSTRAP=true

		log-helper info "Openldap DB and Config directories are empty..."
		log-helper info "Creating new LDAP Server"

		cd /container/service/slapd/assets/ldif
		cp ../templates/config.ldif.tmpl config.ldif
		cp ../templates/data.ldif.tmpl data.ldif
		cp ../templates/ppolicy.ldif.tmpl ppolicy.ldif
		sed -i "s/{{LDAP_BASEDN}}/${BASEDN}/g" config.ldif
		sed -i "s/{{LDAP_ADMIN_PASSWORD}}/${PASS}/g" config.ldif
		sed -i "s|{{LDAP_TLS_CA_CRT_PATH}}|${LDAP_TLS_CA_CRT_PATH}|g" config.ldif
		sed -i "s|{{LDAP_TLS_CRT_PATH}}|${LDAP_TLS_CRT_PATH}|g" config.ldif
		sed -i "s|{{LDAP_TLS_KEY_PATH}}|${LDAP_TLS_KEY_PATH}|g" config.ldif
		sed -i "s|{{LDAP_TLS_CIPHER_SUITE}}|${LDAP_TLS_CIPHER_SUITE}|g" config.ldif
		sed -i "s|{{LDAP_TLS_DH_PARAM_PATH}}|${LDAP_TLS_DH_PARAM_PATH}|g" config.ldif
		sed -i "s/{{LDAP_TLS_PROTOCOL_MIN}}/${LDAP_TLS_PROTOCOL_MIN}/g" config.ldif
		sed -i "s/{{LDAP_TLS_VERIFY_CLIENT}}/${LDAP_TLS_VERIFY_CLIENT}/g" config.ldif
		sed -i "s/{{LDAP_BASEDN}}/${BASEDN}/g" data.ldif
		sed -i "s/{{LDAP_ADMIN_PASSWORD}}/${PASS}/g" data.ldif
		sed -i "s/{{LDAP_ORGANIZATION}}/${ORG_NAME}/g" data.ldif
		sed -i "s/{{LDAP_BASEDN}}/${BASEDN}/g" ppolicy.ldif

		log-helper info "Creating OpenLDAP Database: START"

		cd /container/service/slapd/assets
		slapadd -n 0 -F /etc/ldap/slapd.d -l ldif/config.ldif
		slapadd -n 0 -F /etc/ldap/slapd.d -l schema/memberof.ldif
		slapadd -n 0 -F /etc/ldap/slapd.d -l schema/sudo.ldif
		slapadd -n 0 -F /etc/ldap/slapd.d -l schema/openssh-lpk.ldif
		slapadd -n 0 -F /etc/ldap/slapd.d -l ldif/ppolicy.ldif
		slapadd -n 0 -F /etc/ldap/slapd.d -l ldif/auditlog.ldif

		slapadd -n 1 -F /etc/ldap/slapd.d -l ldif/data.ldif

		log-helper info "Creating OpenLDAP Database: END"
	elif [ ! -z "$(ls -A /var/lib/ldap | grep -v lost+found)" ] &&     \
	   [ -z "$(ls -A /etc/ldap/slapd.d | grep -v lost+found)" ]; then
		log-helper error "Error: The database directory /var/lib/ldap is empty but not the config directory /etc/ldap/slapd.d"
		exit 1
	elif [ -z "$(ls -A /var/lib/ldap | grep -v lost+found)" ] &&     \
	   [ ! -z "$(ls -A /etc/ldap/slapd.d | grep -v lost+found)" ]; then
		log-helper error "Error: The config directory /etc/ldap/slapd.d is empty but not the data directory /var/lib/ldap"
		exit 1
	fi

	touch $FIRST_START_DONE
fi

#chown -R ldap:ldap /etc/ldap/slapd.d /run/slapd /var/log/ldap /var/lib/ldap /etc/ldap/tls
chown -R nginx:nginx /etc/ldap/slapd.d /run/slapd /var/log/ldap /var/lib/ldap /etc/ldap/tls

exit 0
