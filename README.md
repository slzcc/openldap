# Centos-OpenLDAP

Project 使用的 Centos 镜像作为作为基础镜像进行构建，部分实现过程参照 https://github.com/osixia/docker-openldap 项目。

默认镜像使用 TLS 部署 OpenLDAP，如果不需要则通过修改环境变量(slapd/default-env)进行配置即可。

创建 local 数据目录: 
```
$ mkdir -p /data/openldap/ldap /data/openldap/slapd.d /data/openldap/certs
```

## 启动 OpenLDAP Server
`强调，hostname 是必须的，所有的配置几乎都围绕着 HOSTNAME 进行，则 LADP_DOMAIN 是定义自己的域，如果不填则表示默认(测试使用) 请合理使用!`
```
$ docker run -d -p 389:389 -p 639:639 \
--restart always \
--name openldap-server \
--hostname shileizcc.com \
-e LDAP_DOMAIN=shileizcc.com \
-e LDAP_ADMIN_PASSWORD=shileizcc \
-v /data/openldap/ldap:/var/lib/ldap \
-v /data/openldap/slapd.d:/etc/openldap/slapd.d \
-v /data/openldap/certs:/container/service/slapd/certs \
slzcc/openldap:0.1.3
```
添加组织与用户：
```
$ docker exec -it openldap-server bash
$ cat << EOF | ldapadd -x -D "cn=admin,dc=shileizcc,dc=com" -w shileizcc  -H ldap://shileizcc.com
dn: ou=IT,dc=shileizcc,dc=com
ou: IT
objectClass: top
objectClass: organizationalUnit

dn: cn=Ops,ou=IT,dc=shileizcc,dc=com
cn: Ops
gidNumber: 500
objectClass: posixGroup
objectClass: top

dn: cn=shilei,cn=ops,ou=IT,dc=shileizcc,dc=com
uid: shilei
cn: shilei
sn: shi
givenName: lei
displayName: shilei
objectClass: posixAccount
objectClass: top
objectClass: person
objectClass: shadowAccount
objectClass: inetOrgPerson
uidNumber: 1009
gidNumber: 1009
gecos: System Manager
loginShell: /bin/bash
homeDirectory: /home/shilei
userPassword: shilei
shadowLastChange: 17654
shadowMin: 0
shadowMax: 99999
shadowWarning: 7
shadowExpire: -1
employeeNumber: 18002
homePhone: 0531-xxxxxxxx
mobile: 152xxxxxxxxx
mail: shileizcc@126.com
postalAddress: BeiJing
initials: Test
EOF
```
## 启动 Web UI
```
$ docker run -d -p 18080:80 --name phpldapadmin \
--restart always \
-e PHPLDAPADMIN_LDAP_HOSTS=10.140.0.2 \
-e PHPLDAPADMIN_HTTPS=false \
osixia/phpldapadmin:latest
```

## 开启 Multi Master Replication
```
$ LDAP_CID=$(docker run --hostname ldap.example.org --env LDAP_REPLICATION=true -e LDAP_DOMAIN=example.org -e LDAP_ADMIN_PASSWORD=admin -d -e LDAP_REMOVE_CONFIG_AFTER_SETUP=false  slzcc/openldap:0.1.3)
$ LDAP_IP=$(docker inspect -f "{{ .NetworkSettings.IPAddress }}" $LDAP_CID)

$ LDAP2_CID=$(docker run --hostname ldap2.example.org --env LDAP_REPLICATION=true -e LDAP_DOMAIN=example.org -e LDAP_ADMIN_PASSWORD=admin -d  -e LDAP_REMOVE_CONFIG_AFTER_SETUP=false  slzcc/openldap:0.1.3)
$ LDAP2_IP=$(docker inspect -f "{{ .NetworkSettings.IPAddress }}" $LDAP2_CID)

$ docker exec $LDAP_CID bash -c "echo $LDAP2_IP ldap2.example.org >> /etc/hosts"
$ docker exec $LDAP2_CID bash -c "echo $LDAP_IP ldap.example.org >> /etc/hosts"
```
测试: 添加新用户
```
$ docker exec $LDAP_CID ldapadd -x -D "cn=admin,dc=example,dc=org" -w admin -f /container/service/slapd/test/new-user.ldif -H ldap://ldap.example.org -ZZ
```
检验是否添加用户并同步
```
$ docker exec $LDAP2_CID ldapsearch -x -H ldap://ldap.example.org -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w admin -ZZ
# or
$ docker exec $LDAP2_CID ldapsearch -x -H ldap://ldap2.example.org -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w admin -ZZ
```

可以在 slapd/config/bootstrap/ldif/custom 目录内添加自定义的 ldif，目前已经加入了部分可能使用到的 schema。

如果修改修改自定义的 CA，则通过 ssl/config/ 进行修改 cfssl json 文件进行定制。(目前不支持自定义上传 CA 证书)。
