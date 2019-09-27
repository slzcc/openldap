#!/bin/bash -e

ulimit -n 1024

/usr/local/bin/initial_ldap.sh

if [ "${LDAP_TLS,,}" == "true" ]; then

cat > /supervisord.conf <<EOF
[supervisord]
pidfile = /var/run/supervisord.pid
nodaemon = true

[unix_http_server]
file = /var/run/supervisor.sock
chmod = 0777

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl = unix:///var/run/supervisor.sock
;serverurl=http://127.0.0.1:9001

[program:slapd]
user = root
command = /usr/sbin/slapd -h "ldap://$HOSTNAME ldaps://$HOSTNAME ldapi:///" -u ldap -g ldap -d $LDAP_LOG_LEVEL
autostart=true
startsecs=3
startretries=3
autorestart=true
priority=600
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOF

else

cat > /supervisord.conf <<EOF
[supervisord]
pidfile = /var/run/supervisord.pid
nodaemon = true

[unix_http_server]
file = /var/run/supervisor.sock
chmod = 0777

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl = unix:///var/run/supervisor.sock
;serverurl=http://127.0.0.1:9001

[program:slapd]
user = root
command = /usr/sbin/slapd -h "ldap://$HOSTNAME ldapi:///" -u ldap -g ldap -d $LDAP_LOG_LEVEL
autostart=true
startsecs=3
startretries=3
autorestart=true
priority=600
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOF

fi

sleep 2

exec /usr/bin/supervisord -c /supervisord.conf


