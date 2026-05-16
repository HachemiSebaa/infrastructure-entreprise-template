# Infrastructure Entreprise — Template ANSSI

Template Ansible pour déployer une infrastructure Linux d'entreprise conforme aux recommandations de l'**ANSSI**.

Conçu pour être réutilisable, versionné et applicable rapidement sur un nouveau parc.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │           Réseau d'entreprise            │
                    │                                          │
          ┌─────────▼─────────┐                               │
          │   Bastion SSH     │  10.0.0.5                     │
          └─────────┬─────────┘                               │
                    │                                          │
       ┌────────────┼────────────┐                            │
       │            │            │                            │
┌──────▼──────┐ ┌───▼───┐ ┌────▼────┐                       │
│  Web x2     │ │  DB   │ │Monitor  │                        │
│10.0.1.10/11 │ │10.0.2 │ │10.0.3   │                        │
└─────────────┘ └───────┘ └─────────┘                       │
                    │                                          │
                    └─────────────────────────────────────────┘
```

## Rôles

| Rôle | Description |
|------|-------------|
| `common` | Hostname, DNS, NTP, timezone |
| `anssi-hardening` | Sécurisation système (SSH, kernel, comptes, firewall, logs, filesystem) |
| `nginx` | Serveur web |
| `postgresql` | Base de données PostgreSQL |
| `monitoring` | Stack de supervision |

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

### Monitoring
- Prometheus + Grafana + Alertmanager + Node Exporter
- Alertes : instance down, CPU, RAM, disque, échecs SSH

## Prérequis

- Ansible >= 2.12
- Python 3 sur les cibles
- Ubuntu 22.04 LTS ou Debian 12
- Clé SSH déployée sur les cibles

## Utilisation

```bash
git clone https://github.com/HachemiSebaa/infrastructure-entreprise-template.git
cd infrastructure-entreprise-template

# Adapter l'inventaire
vim inventory/production/hosts.yml
vim inventory/production/group_vars/all.yml

# Déploiement complet
ansible-playbook playbooks/site.yml

# Sécurisation uniquement
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
    └── monitoring/
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
