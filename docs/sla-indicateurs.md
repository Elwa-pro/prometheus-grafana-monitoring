# Cadre SLA et catalogue d'indicateurs

> Contexte simulé : le client et ses exigences (SLA) sont fictifs, définis pour ce TP. Ils servent de fil conducteur pour choisir les indicateurs et les seuils.

## 1. Service supervisé

Une application web interne hébergée sur `srv-web01` (nginx), supervisée par `srv-monitor` (Prometheus, Alertmanager, Grafana). Environnement `lab`, réseau 192.168.255.0/24.

## 2. Engagements de service (SLA simulés)

| Engagement | Valeur | Conséquence pour la supervision |
|---|---|---|
| Disponibilité mensuelle du site web | 99,5 % (environ 3 h 36 d'indisponibilité tolérée par mois) | sonde HTTP toutes les 15 s, alerte si le site est inaccessible 1 min |
| Temps de réponse du site | moins de 500 ms | alerte si la durée de la sonde dépasse 500 ms pendant 5 min |
| Détection d'un incident | moins de 2 minutes | intervalle de collecte 15 s, alertes en `for: 1m` ou `2m` |
| Mises à jour de sécurité | appliquées sous 30 jours | indicateur du nombre de mises à jour de sécurité en attente |
| Capacité | aucune saturation (CPU, mémoire, disque) | alertes à 80 % (warning) et 90 % (critical), prévision de saturation disque |

## 3. Catalogue des indicateurs

### 3.1 Ressources (srv-monitor et srv-web01)

| Indicateur | Requête PromQL | Warning | Critical |
|---|---|---|---|
| CPU utilisé (%) | `100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)` | > 80 % pendant 5 min | > 90 % pendant 5 min |
| Mémoire utilisée (%) | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` | > 85 % | > 95 % |
| Disque `/` utilisé (%) | `100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)` | > 80 % | > 90 % |
| Disque plein dans 4 h | `predict_linear(node_filesystem_avail_bytes{mountpoint="/"}[1h], 4 * 3600) < 0` | oui | - |
| Charge (load 5) par CPU | `node_load5 / count by (instance) (node_cpu_seconds_total{mode="idle"})` | > 2 | > 4 |
| Redémarrage récent | `time() - node_boot_time_seconds < 300` | oui | - |
| Réseau reçu (o/s) | `rate(node_network_receive_bytes_total{device="ens160"}[2m])` | suivi (tableau de bord) | - |

### 3.2 Sécurité

| Indicateur | Source | Seuil d'alerte |
|---|---|---|
| Hôte injoignable | `up{job="node"} == 0` | 1 min, critical |
| Services de sécurité actifs (sshd, firewalld, chronyd) | `node_systemd_unit_state{name=~"sshd.service\|firewalld.service\|chronyd.service",state="active"} == 0` | 1 min, critical |
| Échecs de connexion SSH sur 5 min | fichier textfile alimenté par `journalctl` | > 10, warning |
| Mises à jour de sécurité en attente | fichier textfile alimenté par `dnf updateinfo` | > 0 depuis plus de 7 j, warning |
| SELinux en mode `Enforcing` | fichier textfile | différent de 1, critical |
| Expiration du certificat TLS | `blackbox_exporter` (`probe_ssl_earliest_cert_expiry`) | moins de 14 j, warning |
| Accès aux métriques protégé (TLS + authentification) | `scripts/enable_tls_node_exporter.sh` | contrôle manuel (réponse 401 sans identifiants) |

### 3.3 Performance applicative (nginx)

| Indicateur | Requête PromQL | Seuil |
|---|---|---|
| Site accessible | `probe_success{job="blackbox_http"}` | `== 0` pendant 1 min, critical |
| Temps de réponse (s) | `probe_duration_seconds{job="blackbox_http"}` | > 0,5 pendant 5 min, warning |
| Code HTTP | `probe_http_status_code` | différent de 200, critical |
| nginx répond à son exporter | `nginx_up` | `== 0`, critical |
| Requêtes par seconde | `rate(nginx_http_requests_total[2m])` | suivi |
| Connexions actives | `nginx_connections_active` | suivi |

## 4. Lien avec les critères de performance

- **Indicateurs pertinents** : chaque ligne répond à un engagement du tableau du paragraphe 2.
- **Tenant compte des SLA** : seuils et durées (`for`) déduits des engagements.
- **Exhaustivité** : trois familles couvertes, ressources, sécurité et performance applicative.

## 5. Limites

- Les SLA sont des hypothèses de travail, pas un contrat réel.
- Les seuils sont posés a priori ; en exploitation réelle, on les ajusterait après quelques semaines de mesures.
- La latence est mesurée par une sonde unique (pas un percentile applicatif réel).
- Certains indicateurs du catalogue sont suivis sans règle d'alerte dans cette version (charge, redémarrage récent, code HTTP, expiration du certificat).
