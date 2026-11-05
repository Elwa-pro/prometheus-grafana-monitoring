#!/bin/bash
# Metriques de securite pour node_exporter (textfile collector)
OUT=/var/lib/node_exporter/textfile/security.prom
FAIL=$(journalctl -u sshd --since "5 min ago" | grep -c "Failed password")
UPD=$(dnf updateinfo list --security -q 2>/dev/null | grep -c "Sec")
[ "$(getenforce)" = "Enforcing" ] && SEL=1 || SEL=0
cat > $OUT.tmp <<EOT
node_ssh_failed_logins_5m $FAIL
node_security_updates_pending $UPD
node_selinux_enforcing $SEL
EOT
mv $OUT.tmp $OUT
