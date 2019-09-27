FROM centos:7
RUN yum install -y epel-release
RUN yum install -y openldap openldap-servers openldap-clients openldap-devel compat-openldap migrationtools openssl cyrus-sasl krb5-server-ldap krb5-workstation krb5-auth-dialog krb5-libs cyrus-sasl-ldap cyrus-sasl-md5
RUN cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG && \
    chown -R ldap.ldap /etc/openldap/ && \
    chown -R ldap.ldap /var/lib/ldap
COPY initial_ldap.sh /usr/local/bin/initial_ldap.sh
COPY process.sh /usr/local/bin/process.sh
COPY slapd /container/service/slapd
COPY log-helper /usr/local/bin/log-helper
COPY ssl /container/service/ssl

RUN mv /var/lib/ldap /opt/ && \
    mv /etc/openldap /opt/

ENV CONTAINER_SERVICE_DIR=/container/service \
    LDAP_LOG_LEVEL=256

RUN curl -o /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 && \
    curl -o /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 && \
    chmod +x /usr/local/bin/cfssl*

EXPOSE 389 639
 
CMD ["/usr/local/bin/process.sh"]
