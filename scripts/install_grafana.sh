#!/bin/bash
# Installe Grafana depuis le depot officiel, le durcit et ouvre 3000 pour le poste d'administration
set -e
cat > /etc/yum.repos.d/grafana.repo <<'REPO'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
REPO
dnf install -y grafana
# Durcissement par variables d'environnement (lues par le service)
cat >> /etc/sysconfig/grafana-server <<'ENV'
GF_USERS_ALLOW_SIGN_UP=false
GF_AUTH_ANONYMOUS_ENABLED=false
GF_ANALYTICS_REPORTING_ENABLED=false
GF_ANALYTICS_CHECK_FOR_UPDATES=false
GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false
GF_SECURITY_DISABLE_GRAVATAR=true
GF_SECURITY_COOKIE_SAMESITE=strict
ENV
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.255.1" port port="3000" protocol="tcp" accept'
firewall-cmd --reload
systemctl daemon-reload
systemctl enable --now grafana-server
sleep 5
systemctl is-active grafana-server
ss -tlnp | grep ':3000 '
