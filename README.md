# Infrastructure Entreprise — Template ANSSI

Template Ansible pour déployer une infrastructure Linux d'entreprise conforme aux recommandations de l'**ANSSI**.

Conçu pour être réutilisable, versionné et applicable rapidement sur un nouveau parc.

## Démarrage rapide

```bash
git clone https://github.com/HachemiSebaa/infrastructure-entreprise-template.git
cd infrastructure-entreprise-template
./wizard.sh
```

Le wizard guide la configuration complète de l'infrastructure de façon interactive : noms des serveurs, adresses IP (avec suggestions), domaine AD, mots de passe, politique de sécurité, alertes. Il génère automatiquement tous les fichiers d'inventaire et de variables Ansible.

Une fois le wizard terminé :

```bash
# Chiffrer les mots de passe
ansible-vault encrypt vault.yml

# Vérifier la connectivité
ansible all -m ping --ask-vault-pass

# Déployer
ansible-playbook playbooks/site.yml --ask-vault-pass
```

## Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │             Réseau d'entreprise             │
                    │                                             │
          ┌─────────▼─────────┐     ┌──────────────────┐          │
          │   Bastion SSH     │     │ DC01 / DC02      │          │
          │   10.0.0.5        │     │ Active Directory │          │
          └─────────┬─────────┘     │ 10.0.4.10/11     │          │
                    │               └──────────────────┘          │
       ┌────────────┼────────────┐                                │
       │            │            │                                │
┌──────▼──────┐ ┌───▼───┐ ┌────▼────┐                             │
│  Web x2     │ │  DB   │ │Monitor  │                             │
│10.0.1.10/11 │ │10.0.2 │ │10.0.3   │                             │
└─────────────┘ └───────┘ └─────────┘                             │
                    │                                             │
                    └─────────────────────────────────────────────┘
```

## Rôles

| Rôle | OS cible | Description |
|------|----------|-------------|
| `common` | Linux | Hostname, DNS, NTP, timezone |
| `anssi-hardening` | Linux | Sécurisation système (SSH, kernel, comptes, firewall, logs, filesystem) |
| `nginx` | Linux | Serveur web |
| `postgresql` | Linux | Base de données PostgreSQL |
| `monitoring` | Linux | Stack de supervision |
| `active-directory` | Windows Server | Active Directory, GPO, LDAPS, audit |
| `dhcp-windows` | Windows Server | DHCP Server, scopes, réservations, failover |

## Ce qui est configuré

### SSH (ANSSI R67)
- Algorithmes modernes uniquement : Ed25519, ChaCha20, AES-GCM
- Authentification par clé uniquement, root désactivé
- Forwarding et X11 désactivés
- Bannière légale

### Kernel
- Sysctl : anti-spoofing, anti-redirect, SYN cookies, ASLR
- Modules blacklistés : USB storage, DCCP, SCTP, filesystems inutiles
- Protection GRUB, core dumps désactivés

### Comptes (ANSSI R31, R33)
- PAM pwquality : longueur min 12, complexité, historique
- Root verrouillé, comptes système inutiles supprimés
- sudo avec mot de passe obligatoire

### Firewall
- UFW, deny par défaut en entrée
- Seuls les ports nécessaires ouverts par rôle

### Logs (ANSSI R73)
- auditd : surveillance fichiers sensibles, escalade de privilèges, appels système
- Centralisation rsyslog, rétention 90 jours

### Filesystem (ANSSI R22)
- `/tmp` et `/dev/shm` : nodev, nosuid, noexec
- Permissions strictes sur `/etc/shadow`, `/etc/sudoers`, cron

### Nginx
- TLS 1.2/1.3, ciphers modernes, OCSP stapling
- Headers : HSTS, CSP, X-Frame-Options, X-Content-Type-Options
- Rate limiting, server tokens désactivés

### PostgreSQL
- Authentification scram-sha-256, SSL activé
- pg_hba strict, logs DDL et connexions
- Droits PUBLIC révoqués

### Active Directory (Windows Server)
- Forêt AD + contrôleurs de domaine (primaire + secondaire)
- OUs, groupes de sécurité, comptes utilisateurs
- Politique de mots de passe domaine + Fine-Grained PSO pour les admins (16 car. min)
- SMBv1 désactivé, NTLMv1 désactivé, NTLMv2 uniquement
- WDigest désactivé (évite stockage mots de passe en clair en mémoire)
- Protection LSA (RunAsPPL), Credential Guard
- LDAPS avec channel binding et LDAP signing obligatoire
- Audit avancé : Kerberos, logons, changements AD, utilisation des privilèges
- Journaux sécurité 200 Mo, transmission vers SIEM

### DHCP Windows Server
- Installation et autorisation du rôle DHCP dans Active Directory
- Scopes configurables : plage, masque, durée de bail, routeur, DNS, domaine
- Exclusions et réservations par adresse MAC
- Failover DHCP entre DC01 et DC02 (Hot Standby ou Load Balance)
- Audit activé, DNS dynamique sécurisé uniquement, détection de conflits

### Monitoring
- Prometheus + Grafana + Alertmanager + Node Exporter
- Alertes : instance down, CPU, RAM, disque, échecs SSH

## Prérequis

**Linux**
- Ansible >= 2.12
- Python 3 sur les cibles
- Ubuntu 22.04 LTS ou Debian 12
- Clé SSH déployée sur les cibles

**Windows / Active Directory**
- Windows Server 2019 ou 2022
- WinRM HTTPS activé sur les cibles (`Enable-PSRemoting`)
- Collection Ansible : `ansible-galaxy collection install ansible.windows community.windows`
- Kerberos configuré sur le nœud de contrôle (`python3-gssapi`)

## Utilisation

```bash
git clone https://github.com/HachemiSebaa/infrastructure-entreprise-template.git
cd infrastructure-entreprise-template

# Adapter l'inventaire
vim inventory/production/hosts.yml
vim inventory/production/group_vars/all.yml

# Déploiement complet (Linux)
ansible-playbook playbooks/site.yml

# Active Directory uniquement
ansible-playbook playbooks/active-directory.yml

# Sécurisation Linux uniquement
ansible-playbook playbooks/hardening.yml

# Dry-run
ansible-playbook playbooks/site.yml --check --diff
```

## Structure

```
.
├── ansible.cfg
├── inventory/
│   ├── production/
│   │   ├── hosts.yml
│   │   └── group_vars/all.yml
│   └── staging/
│       └── hosts.yml
├── playbooks/
│   ├── site.yml
│   └── hardening.yml
└── roles/
    ├── common/
    ├── anssi-hardening/
    ├── nginx/
    ├── postgresql/
    ├── monitoring/
    └── active-directory/
```

## Références ANSSI

- R12 — Modules noyau
- R14 — Services inutiles
- R22 — Options de montage
- R31 — Politique de mots de passe
- R33 — Compte root
- R55 — Core dumps
- R62 — sudo
- R67 — SSH
- R73 — auditd

## Licence

MIT
