# Incidents simulés : interprétation des alertes

Chaque incident est provoqué volontairement sur `srv-web01`, puis diagnostiqué à partir de l'alerte reçue, corrigé et vérifié.

| N° | Incident provoqué | Alerte(s) reçue(s) | Route | Interprétation | Correction | Retour à la normale |
|---|---|---|---|---|---|---|
| 1 | Arrêt du service nginx (`systemctl stop nginx`) | `NginxArrete`, `SiteInaccessible` (critical) | astreinte | Le service web est tombé, pas la machine : `HoteInjoignable` n'est pas déclenchée, node_exporter et nginx_exporter répondent encore. Le site n'est plus joignable (SLA de disponibilité touché). | `systemctl start nginx` | Alertes inactives, `nginx_up = 1`, `probe_success = 1` |
| 2 | Saturation CPU : processus `dd if=/dev/zero of=/dev/null` (1 vCPU sur srv-web01) | `CPUEleve` (warning), `CPUCritique` (critical) | astreinte (le warning est masqué par l'inhibition) | Un processus consomme tout le CPU de façon prolongée (plus de 5 min) : risque de lenteur du site (SLA temps de réponse). Le délai `for: 5m` a évité une alerte sur un simple pic. | Identifier le processus avec `top`, puis `pkill -x dd` | Alertes inactives, CPU idle 100 % |
| 3 | 13 tentatives de connexion SSH échouées (compte inexistant `admin`) depuis srv-monitor vers srv-web01 | `EchecsConnexionSSH` (warning) | equipe-systeme | Comportement de force brute : plus de 10 échecs en 5 min depuis une même IP sur un compte courant inexistant. Le journal confirme `Failed password for invalid user admin from 192.168.255.10`. Faiblesse constatée : `passwordauthentication yes` sur srv-web01. | Aucun correctif appliqué en lab (hors périmètre) ; mesures recommandées : `PasswordAuthentication no` une fois les clés en place, Fail2Ban, filtrage par pare-feu des IP sources | Alerte retombée toute seule quand les échecs sortent de la fenêtre de 5 min |
| 4 | Disque `/` de srv-web01 qui se remplit : fichier de 12 Go créé avec `fallocate` (de 9 % à 85 %) | `DisqueRempli80` (warning) ; `DisquePleinDans4h` (warning, faux positif) | equipe-systeme | Saturation du disque racine : risque d'arrêt de nginx et des journaux avant le seuil critique (90 %). Le coupable se trouve avec `du -sh` ; ici un gros fichier dans `/var/tmp`. | Suppression du fichier (`rm`), disque revenu à 9 % | `DisqueRempli80` inactive moins d'une minute après la suppression ; `DisquePleinDans4h` reste active (voir détail) |

## Détail de l'incident 1

1. Symptôme : deux alertes critical en état FIRING dans Prometheus au bout d'environ 1 minute (`for: 1m`), puis visibles dans Alertmanager sous le récepteur `astreinte`.
2. Diagnostic : `systemctl is-active nginx nginx_exporter node_exporter` sur srv-web01 donne `inactive`, `active`, `active`. `curl -I http://192.168.255.11` ne reçoit aucune réponse.
3. Cause : nginx arrêté. Les deux exporters tournent, la machine est donc joignable.
4. Correction : `sudo systemctl start nginx`.
5. Vérification : alertes revenues à inactive dans Prometheus.

## Détail de l'incident 2

1. Symptôme : `CPUEleve` et `CPUCritique` passent en PENDING (condition vraie, délai `for: 5m` en cours), puis en FIRING environ 5 minutes plus tard. Alertmanager ne notifie que `CPUCritique` (route astreinte) : l'alerte warning de la même instance est inhibée.
2. Diagnostic : `top -bn1` sur srv-web01 montre le processus `dd` (utilisateur wawad) à environ 91 % de CPU, charge moyenne 1,00 pour 1 vCPU.
3. Cause : processus de charge lancé volontairement (simulation d'un processus fou).
4. Correction : `pkill -x dd`, puis contrôle (`pgrep -x dd` ne renvoie rien, CPU idle 100 %).
5. Vérification : plus aucune alerte pending ou firing dans Prometheus après la fenêtre de calcul (`rate` sur 2 min).

## Détail de l'incident 3

1. Provocation : tentatives de connexion avec un faux mot de passe (`SSH_ASKPASS` pour automatiser la saisie) sur le compte inexistant `admin`, en deux rafales (la protection `PerSourcePenalties` d'OpenSSH coupe les connexions d'une même source après environ 8 échecs : `Connection reset`).
2. Mesure : le script `security_metrics.sh` compte les « Failed password » des 5 dernières minutes dans le journal de sshd (`node_ssh_failed_logins_5m`) ; valeur 13 sur srv-web01, 0 sur srv-monitor. Premier essai : 5 seulement, car les 8 premiers échecs étaient sortis de la fenêtre de 5 min avant le recalcul (le compteur est un instantané, pas un cumul).
3. Alerte : `EchecsConnexionSSH` FIRING au prochain recalcul du timer (toutes les 5 min) puis scrape, notifiée sur la route equipe-systeme (severity warning).
4. Diagnostic : `journalctl -u sshd` sur srv-web01 donne la source (192.168.255.10) et le compte visé (invalid user admin) ; `sshd -T` montre `passwordauthentication yes`, `maxauthtries 6`, `permitrootlogin without-password`.
5. Retour à la normale : l'alerte n'est plus active quand les échecs sortent de la fenêtre.

Limite : délai de détection de 0 à 5 min lié au timer (supérieur à l'objectif de 2 min du SLA pour cet indicateur). Pour descendre sous 2 min, il faudrait un timer à 1 min ou un exporter de logs (mtail, Loki).

## Détail de l'incident 4

1. Provocation : `ssh wawad@192.168.255.11 'fallocate -l 12G /var/tmp/gros_fichier.bin'` crée instantanément un fichier de 12 Go sur le disque `/` (16 Go) de srv-web01, sans droits administrateur. `df -h /` passe de 9 % à 85 %.
2. Détection : `DisqueRempli80` (`> 80 %`, `for: 5m`) passe en PENDING (valeur 84 %), puis en FIRING après 5 min. `DisqueRempli90` ne se déclenche pas (seuil non atteint).
3. Notification : Alertmanager l'affecte à la route equipe-systeme (severity warning), car ce n'est pas critique tant qu'il reste de la place.
4. Diagnostic : `df -h /` donne le taux d'occupation, `du -sh /var/tmp/*` désigne le fichier responsable.
5. Correction : `rm /var/tmp/gros_fichier.bin` ; `df -h /` repasse à 9 % ; `DisqueRempli80` redevient inactive à l'évaluation suivante.
6. Constat : `DisquePleinDans4h` (`predict_linear` sur 1 h) est passée en PENDING puis en FIRING alors que le disque était déjà revenu à 9 %. La régression linéaire sur 1 h englobe la chute brutale de l'espace libre et en déduit un remplissage rapide. Cette règle convient à une croissance progressive (journaux, base de données), pas à un saut ponctuel.

Limites et améliorations : allonger la fenêtre (`[6h]`) ou ajouter une condition de seuil (n'alerter que si le disque dépasse 50 %) pour réduire les faux positifs ; en production, surveiller aussi les inodes et définir une politique de rotation et de quotas.
