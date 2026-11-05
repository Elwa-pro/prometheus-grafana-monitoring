#!/bin/bash
# Deploie le provisioning Grafana (datasource + dashboard en fichiers) puis redemarre le service
set -e
install -d -o root -g grafana -m 0750 /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
install -d -o grafana -g grafana -m 0750 /var/lib/grafana/dashboards
install -o root -g grafana -m 0640 /tmp/ds.yml /etc/grafana/provisioning/datasources/prometheus.yml
install -o root -g grafana -m 0640 /tmp/dp.yml /etc/grafana/provisioning/dashboards/dashboards.yml
install -o grafana -g grafana -m 0640 /tmp/dash.json /var/lib/grafana/dashboards/supervision-m48.json
restorecon -R /etc/grafana /var/lib/grafana/dashboards
systemctl restart grafana-server
sleep 8
systemctl is-active grafana-server
journalctl -u grafana-server --since "1 min ago" --no-pager | grep -iE "provision|error" | tail -6
