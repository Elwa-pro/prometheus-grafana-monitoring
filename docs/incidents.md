# Incidents simulés : interprétation des alertes

J'ai provoqué chaque incident sur `srv-web01`. Je l'ai ensuite diagnostiqué à partir de l'alerte reçue, corrigé, puis j'ai vérifié le retour à la normale.

| N° | Incident provoqué | Alerte(s) reçue(s) | Route | Interprétation | Correction | Retour à la normale |
|---|---|---|---|---|---|---|
| 1 | Arrêt de nginx (`systemctl stop nginx`) | `NginxArrete`, `SiteInaccessible` (critical) | astreinte | Le service web est tombé, pas la machine : `HoteInjoignable` reste muette parce que node_exporter et nginx_exporter répondent encore. Le site est injoignable, ce qui touche le SLA de disponibilité. | `systemctl start nginx` | Alertes inactives, `nginx_up = 1`, `probe_success = 1` |
| 2 | Saturation CPU : `dd if=/dev/zero of=/dev/null` sur le seul vCPU de srv-web01 | `CPUEleve` (warning), `CPUCritique` (critical) | astreinte (la warning est inhibée) | Un processus occupe tout le CPU pendant plus de 5 min, et le site risque de ralentir (SLA de temps de réponse). Grâce au `for: 5m`, un simple pic n'aurait pas déclenché d'alerte. | Repérer le processus avec `top`, puis `pkill -x dd` | Alertes inactives, CPU idle à 100 % |
| 3 | 13 connexions SSH échouées sur le compte inexistant `admin`, depuis srv-monitor vers srv-web01 | `EchecsConnexionSSH` (warning) | equipe-systeme | Plus de 10 échecs en 5 min depuis une même IP sur un nom de compte courant : c'est le profil d'une attaque par force brute. Le journal le confirme (`Failed password for invalid user admin from 192.168.255.10`), et je relève une faiblesse : `passwordauthentication yes` sur srv-web01. | Pas de correctif en laboratoire. Recommandé : `PasswordAuthentication no` une fois les clés en place, Fail2Ban, filtrage des IP sources par le pare-feu | L'alerte retombe seule quand les échecs sortent de la fenêtre de 5 min |
| 4 | Disque `/` de srv-web01 rempli par un fichier de 12 Go créé avec `fallocate` (de 9 % à 85 %) | `DisqueRempli80` (warning) ; `DisquePleinDans4h` (warning, faux positif) | equipe-systeme | Le disque racine se remplit : nginx et les journaux risquent de s'arrêter avant le seuil critique de 90 %. `du -sh` désigne le coupable, ici un gros fichier dans `/var/tmp`. | Suppression du fichier (`rm`), disque revenu à 9 % | `DisqueRempli80` inactive moins d'une minute après la suppression ; `DisquePleinDans4h` reste active (voir le détail) |

## Incident 1 : nginx arrêté

1. Symptôme : deux alertes critical passent en FIRING dans Prometheus au bout d'environ 1 minute (`for: 1m`), puis arrivent dans Alertmanager sous le récepteur `astreinte`.
2. Diagnostic : sur srv-web01, `systemctl is-active nginx nginx_exporter node_exporter` renvoie `inactive`, `active`, `active`, et `curl -I http://192.168.255.11` ne reçoit aucune réponse.
3. Cause : nginx est arrêté. Les deux exporters tournent, donc la machine est joignable.
4. Correction : `sudo systemctl start nginx`.
5. Vérification : les alertes repassent à inactive dans Prometheus.

## Incident 2 : CPU saturé

1. Symptôme : `CPUEleve` et `CPUCritique` passent en PENDING (la condition est vraie, le délai `for: 5m` court), puis en FIRING environ 5 minutes plus tard. Alertmanager ne notifie que `CPUCritique`, sur la route astreinte, car l'inhibition masque la warning de la même instance.
2. Diagnostic : `top -bn1` sur srv-web01 montre `dd` (utilisateur wawad) à environ 91 % de CPU, avec une charge moyenne de 1,00 pour 1 vCPU.
3. Cause : le processus de charge lancé volontairement, pour simuler un processus qui s'emballe.
4. Correction : `pkill -x dd`, puis `pgrep -x dd` ne renvoie plus rien et le CPU revient à 100 % d'idle.
5. Vérification : une fois la fenêtre de calcul passée (`rate` sur 2 min), plus aucune alerte n'est pending ou firing.

## Incident 3 : échecs de connexion SSH

1. Provocation : des connexions avec un faux mot de passe sur le compte inexistant `admin`, saisies automatiquement grâce à `SSH_ASKPASS`. Elles partent en deux rafales, parce que la protection `PerSourcePenalties` d'OpenSSH coupe une source après environ 8 échecs (`Connection reset`).
2. Mesure : `security_metrics.sh` compte les « Failed password » des 5 dernières minutes dans le journal de sshd (`node_ssh_failed_logins_5m`). La valeur monte à 13 sur srv-web01 et reste à 0 sur srv-monitor. Au premier essai, je n'en ai vu que 5 : les 8 premiers échecs étaient sortis de la fenêtre avant le recalcul, car le compteur donne un instantané et non un cumul.
3. Alerte : `EchecsConnexionSSH` passe en FIRING après le recalcul suivant du timer (toutes les 5 min) et la collecte de Prometheus. Elle est notifiée sur la route equipe-systeme (severity warning).
4. Diagnostic : sur srv-web01, `journalctl -u sshd` donne la source (192.168.255.10) et le compte visé (invalid user admin). `sshd -T` montre `passwordauthentication yes`, `maxauthtries 6` et `permitrootlogin without-password`.
5. Retour à la normale : l'alerte s'éteint quand les échecs sortent de la fenêtre.

Limite : le timer retarde la détection de 0 à 5 minutes, plus que les 2 minutes visées par le SLA pour cet indicateur. Pour passer sous 2 minutes, il faudrait un timer d'une minute ou un exporter de logs (mtail, Loki).

## Incident 4 : disque qui se remplit

1. Provocation : `ssh wawad@192.168.255.11 'fallocate -l 12G /var/tmp/gros_fichier.bin'` crée en un instant un fichier de 12 Go sur le disque `/` (16 Go) de srv-web01, sans droits d'administrateur. `df -h /` passe de 9 % à 85 %.
2. Détection : `DisqueRempli80` (`> 80 %`, `for: 5m`) passe en PENDING à 84 %, puis en FIRING 5 minutes plus tard. `DisqueRempli90` ne se déclenche pas, le seuil n'étant pas atteint.
3. Notification : Alertmanager l'envoie sur la route equipe-systeme (severity warning). Ce n'est pas encore critique tant qu'il reste de la place.
4. Diagnostic : `df -h /` donne le taux d'occupation et `du -sh /var/tmp/*` désigne le fichier responsable.
5. Correction : `rm /var/tmp/gros_fichier.bin`. `df -h /` repasse à 9 % et `DisqueRempli80` redevient inactive à l'évaluation suivante.
6. Constat : `DisquePleinDans4h` (`predict_linear` sur 1 h) est passée en PENDING puis en FIRING alors que le disque était déjà revenu à 9 %. La régression linéaire sur 1 h englobe la chute brutale de l'espace libre et en déduit un remplissage rapide. Cette règle convient à une croissance progressive, comme des journaux ou une base de données, mais pas à un saut ponctuel.

Pour réduire ces faux positifs, on peut allonger la fenêtre (`[6h]`) ou n'alerter que si le disque dépasse déjà 50 %. En production, je surveillerais aussi les inodes, avec une politique de rotation et de quotas.
