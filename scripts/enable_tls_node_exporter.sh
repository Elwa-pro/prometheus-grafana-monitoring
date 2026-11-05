#!/bin/bash
# Active TLS + authentification basic sur node_exporter (srv-monitor), a lancer avec sudo
set -e
D=/etc/node_exporter
dnf install -y httpd-tools > /dev/null
mkdir -p $D
# 1. Certificat auto-signe valable pour les 2 VM
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=node_exporter" \
  -addext "subjectAltName=DNS:srv-monitor,DNS:srv-web01,IP:192.168.255.10,IP:192.168.255.11" \
  -keyout $D/node.key -out $D/node.crt 2> /dev/null
# 2. Mot de passe aleatoire (jamais affiche) et son hash bcrypt
PASS=$(openssl rand -base64 12)
HASH=$(echo "$PASS" | htpasswd -niBC 10 prometheus | cut -d: -f2)
# 3. Fichier de configuration web de node_exporter
printf 'tls_server_config:\n  cert_file: %s/node.crt\n  key_file: %s/node.key\nbasic_auth_users:\n  prometheus: %s\n' $D $D "$HASH" > $D/web.yml
# 4. Cote Prometheus : mot de passe et certificat (CA)
echo "$PASS" > /etc/prometheus/node_pass
cp $D/node.crt /etc/prometheus/node.crt
chown root:prometheus /etc/prometheus/node_pass /etc/prometheus/node.crt
chmod 640 /etc/prometheus/node_pass /etc/prometheus/node.crt
# 5. Droits et SELinux
chown -R root:node_exporter $D
chmod 750 $D
chmod 640 $D/*
restorecon -R $D
# 6. Copie pour srv-monitor -> srv-web01
mkdir -p /tmp/node_tls
cp $D/node.crt $D/node.key $D/web.yml /tmp/node_tls/
chown -R wawad /tmp/node_tls
# 7. node_exporter local lit le fichier web.yml
sed -i 's|^ExecStart=.*|& --web.config.file=/etc/node_exporter/web.yml|' /etc/systemd/system/node_exporter.service
systemctl daemon-reload
systemctl restart node_exporter
systemctl is-active node_exporter
