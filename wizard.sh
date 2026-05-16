#!/usr/bin/env bash
set -euo pipefail

# ─── Couleurs ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
banner() {
  clear
  echo -e "${BOLD}${BLUE}"
  cat << 'EOF'
  ██╗███╗   ██╗███████╗██████╗  █████╗
  ██║████╗  ██║██╔════╝██╔══██╗██╔══██╗
  ██║██╔██╗ ██║█████╗  ██████╔╝███████║
  ██║██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║
  ██║██║ ╚████║██║     ██║  ██║██║  ██║
  ╚═╝╚═╝  ╚═══╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝
   Infrastructure Entreprise — Template ANSSI
EOF
  echo -e "${RESET}"
  echo -e "  ${CYAN}Wizard de configuration du déploiement${RESET}"
  echo -e "  ${YELLOW}Les valeurs entre [crochets] sont les valeurs par défaut.${RESET}"
  echo -e "  ${YELLOW}Appuie sur Entrée pour les accepter.${RESET}\n"
}

section() {
  echo -e "\n${BOLD}${BLUE}━━━  $1  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
}

ok()   { echo -e "  ${GREEN}✔${RESET}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
info() { echo -e "  ${CYAN}→${RESET}  $1"; }
err()  { echo -e "  ${RED}✘${RESET}  $1"; }

ask() {
  local prompt="$1" default="${2:-}" var_name="$3"
  local display_default=""
  [[ -n "$default" ]] && display_default=" ${YELLOW}[$default]${RESET}"
  echo -ne "  ${BOLD}${prompt}${RESET}${display_default} : "
  read -r input
  input="${input:-$default}"
  printf -v "$var_name" '%s' "$input"
}

ask_secret() {
  local prompt="$1" var_name="$2"
  local pass1 pass2
  while true; do
    echo -ne "  ${BOLD}${prompt}${RESET} : "
    read -rs pass1; echo
    echo -ne "  ${BOLD}Confirmer${RESET} : "
    read -rs pass2; echo
    if [[ "$pass1" == "$pass2" ]]; then
      printf -v "$var_name" '%s' "$pass1"
      break
    else
      err "Les mots de passe ne correspondent pas, recommence."
    fi
  done
}

validate_ip() {
  local ip="$1"
  local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  if [[ ! $ip =~ $regex ]]; then return 1; fi
  IFS='.' read -ra parts <<< "$ip"
  for part in "${parts[@]}"; do
    [[ "$part" -gt 255 ]] && return 1
  done
  return 0
}

ask_ip() {
  local prompt="$1" default="$2" var_name="$3"
  while true; do
    ask "$prompt" "$default" "$var_name"
    local val="${!var_name}"
    if validate_ip "$val"; then break
    else err "Adresse IP invalide : $val"; fi
  done
}

ask_int() {
  local prompt="$1" default="$2" min="$3" max="$4" var_name="$5"
  while true; do
    ask "$prompt" "$default" "$var_name"
    local val="${!var_name}"
    if [[ "$val" =~ ^[0-9]+$ ]] && (( val >= min && val <= max )); then break
    else err "Valeur invalide. Entier entre $min et $max attendu."; fi
  done
}

ask_yn() {
  local prompt="$1" default="${2:-o}" var_name="$3"
  local hint="[o/n]"
  [[ "$default" == "o" ]] && hint="${YELLOW}[O/n]${RESET}" || hint="${YELLOW}[o/N]${RESET}"
  echo -ne "  ${BOLD}${prompt}${RESET} ${hint} : "
  read -r input
  input="${input:-$default}"
  input="${input,,}"
  if [[ "$input" == "o" || "$input" == "oui" || "$input" == "y" || "$input" == "yes" ]]; then
    printf -v "$var_name" 'true'
  else
    printf -v "$var_name" 'false'
  fi
}

suggest_ip() {
  local base="$1" last="$2"
  echo "${base}.${last}"
}

# ─── Démarrage ───────────────────────────────────────────────────────────────
banner
echo -e "  Ce wizard va générer :\n"
echo -e "    ${GREEN}•${RESET} inventory/production/hosts.yml"
echo -e "    ${GREEN}•${RESET} inventory/production/group_vars/all.yml"
echo -e "    ${GREEN}•${RESET} inventory/production/group_vars/domain_controllers.yml"
echo -e "    ${GREEN}•${RESET} vault.yml (mots de passe chiffrés Ansible Vault)\n"
echo -ne "  ${BOLD}Appuie sur Entrée pour commencer...${RESET}"
read -r

# ═══════════════════════════════════════════════════════════════════════════════
section "1/8  Réseau général"

ask      "Nom de domaine AD (FQDN)"     "corp.infra.local"  DOMAIN_NAME
ask      "Nom NetBIOS"                  "CORP"               DOMAIN_NETBIOS
ask      "Plage réseau (CIDR)"          "10.0.0.0/8"         NETWORK_RANGE

NET_BASE=$(echo "$NETWORK_RANGE" | cut -d'.' -f1-2)

ask      "Fuseau horaire"               "Europe/Paris"       TIMEZONE
ask      "Serveur NTP primaire"         "0.fr.pool.ntp.org"  NTP1
ask      "Serveur NTP secondaire"       "1.fr.pool.ntp.org"  NTP2

info "Configuration DNS interne"
ask_ip   "DNS primaire"                 "${NET_BASE}.0.1"    DNS1
ask_ip   "DNS secondaire"              "${NET_BASE}.0.2"    DNS2

ok "Réseau configuré : ${DOMAIN_NAME} — ${NETWORK_RANGE}"

# ═══════════════════════════════════════════════════════════════════════════════
section "2/8  Bastion SSH"

ask    "Nom du bastion"                "bastion01"          BASTION_NAME
ask_ip "Adresse IP du bastion"         "${NET_BASE}.0.5"    BASTION_IP
ask_int "Port SSH"                     "22" "1" "65535"     SSH_PORT

ok "Bastion : ${BASTION_NAME} — ${BASTION_IP}:${SSH_PORT}"

# ═══════════════════════════════════════════════════════════════════════════════
section "3/8  Active Directory — Windows Server"

ask_int "Nombre de contrôleurs de domaine" "2" "1" "4"  DC_COUNT

DC_NAMES=(); DC_IPS=()
for (( i=1; i<=DC_COUNT; i++ )); do
  echo -e "\n  ${CYAN}Contrôleur de domaine ${i}${RESET}"
  ask    "  Hostname"   "dc0${i}"                      "DC_NAME_${i}"
  ask_ip "  Adresse IP" "${NET_BASE}.4.$((9+i))"       "DC_IP_${i}"
  DC_NAMES+=("${!DC_NAME_$i}")
  DC_IPS+=("${!DC_IP_$i}")
done

ask "Niveau fonctionnel du domaine" "WinThreshold (2016+)" DC_LEVEL
[[ "$DC_LEVEL" == "WinThreshold (2016+)" ]] && DC_LEVEL="WinThreshold"

echo
ask_secret "Mot de passe Safe Mode (DSRM)"    VAULT_SAFEMODE_PASS
ask_secret "Mot de passe Administrateur AD"   VAULT_AD_ADMIN_PASS

ok "${DC_COUNT} DC(s) configuré(s) pour le domaine ${DOMAIN_NAME}"

# ═══════════════════════════════════════════════════════════════════════════════
section "4/8  Serveurs web (Nginx)"

ask_int "Nombre de serveurs web" "2" "1" "8"   WEB_COUNT

WEB_NAMES=(); WEB_IPS=()
for (( i=1; i<=WEB_COUNT; i++ )); do
  echo -e "\n  ${CYAN}Serveur web ${i}${RESET}"
  ask    "  Hostname"   "web0${i}"                    "WEB_NAME_${i}"
  ask_ip "  Adresse IP" "${NET_BASE}.1.$((9+i))"      "WEB_IP_${i}"
  WEB_NAMES+=("${!WEB_NAME_$i}")
  WEB_IPS+=("${!WEB_IP_$i}")
done

ask_yn "Activer HTTPS (TLS)" "o" TLS_ENABLED
ask    "Nom de domaine public (vhost)" "www.${DOMAIN_NAME}" WEB_VHOST

ok "${WEB_COUNT} serveur(s) web configuré(s)"

# ═══════════════════════════════════════════════════════════════════════════════
section "5/8  Base de données (PostgreSQL)"

ask    "Hostname"                  "db01"                   DB_NAME
ask_ip "Adresse IP"                "${NET_BASE}.2.10"       DB_IP
ask    "Nom de la base de données" "appdb"                  DB_DBNAME
ask    "Utilisateur applicatif"    "appuser"                DB_USER
ask_secret "Mot de passe base de données"                   VAULT_DB_PASS

ok "Base de données : ${DB_NAME} — ${DB_IP} — base ${DB_DBNAME}"

# ═══════════════════════════════════════════════════════════════════════════════
section "6/8  Monitoring (Prometheus / Grafana)"

ask    "Hostname"                  "mon01"                  MON_NAME
ask_ip "Adresse IP"                "${NET_BASE}.3.10"       MON_IP
ask    "Email pour les alertes"    "soc@${DOMAIN_NAME}"     ALERT_EMAIL
ask_secret "Mot de passe Grafana (admin)"                   VAULT_GRAFANA_PASS

ask_yn "Configurer un webhook Slack pour les alertes critiques ?" "n" SLACK_ENABLED
SLACK_WEBHOOK=""
if [[ "$SLACK_ENABLED" == "true" ]]; then
  ask "URL du webhook Slack" "" SLACK_WEBHOOK
fi

ok "Monitoring : ${MON_NAME} — ${MON_IP}"

# ═══════════════════════════════════════════════════════════════════════════════
section "7/8  Politique de sécurité des mots de passe (ANSSI R31)"

ask_int "Longueur minimale"           "12"  "8"  "64"   PASS_MIN_LEN
ask_int "Durée maximale (jours)"      "90"  "30" "365"  PASS_MAX_DAYS
ask_int "Durée minimale (jours)"      "1"   "0"  "30"   PASS_MIN_DAYS
ask_int "Historique (nb anciens mdp)" "12"  "5"  "24"   PASS_HISTORY
ask_int "Verrouillage après X échecs" "5"   "3"  "10"   PASS_LOCKOUT

ok "Politique de mots de passe configurée"

# ═══════════════════════════════════════════════════════════════════════════════
section "8/8  Utilisateur Ansible (déploiement)"

ask      "Nom d'utilisateur Ansible sur les cibles" "ansible"        ANSIBLE_USER
ask      "Chemin clé SSH privée"                    "~/.ssh/id_ed25519" ANSIBLE_KEY

ask_yn "Activer IPv6 ?" "n" IPV6_ENABLED
IPV6_DISABLE=1
[[ "$IPV6_ENABLED" == "true" ]] && IPV6_DISABLE=0

# ═══════════════════════════════════════════════════════════════════════════════
section "Récapitulatif"

echo -e "  ${BOLD}Réseau${RESET}"
echo -e "    Domaine      : ${GREEN}${DOMAIN_NAME}${RESET} (NetBIOS : ${DOMAIN_NETBIOS})"
echo -e "    Plage réseau : ${GREEN}${NETWORK_RANGE}${RESET}"
echo -e "    DNS          : ${DNS1}, ${DNS2}"
echo -e "    NTP          : ${NTP1}, ${NTP2}"

echo -e "\n  ${BOLD}Serveurs${RESET}"
echo -e "    Bastion      : ${GREEN}${BASTION_NAME}${RESET} — ${BASTION_IP} (SSH :${SSH_PORT})"

for (( i=1; i<=DC_COUNT; i++ )); do
  echo -e "    DC ${i}          : ${GREEN}${DC_NAMES[$((i-1))]}${RESET} — ${DC_IPS[$((i-1))]}"
done

for (( i=1; i<=WEB_COUNT; i++ )); do
  echo -e "    Web ${i}         : ${GREEN}${WEB_NAMES[$((i-1))]}${RESET} — ${WEB_IPS[$((i-1))]}"
done

echo -e "    Base données : ${GREEN}${DB_NAME}${RESET} — ${DB_IP}"
echo -e "    Monitoring   : ${GREEN}${MON_NAME}${RESET} — ${MON_IP}"

echo -e "\n  ${BOLD}Sécurité${RESET}"
echo -e "    Mots de passe : min ${PASS_MIN_LEN} car., max ${PASS_MAX_DAYS}j, historique ${PASS_HISTORY}"
echo -e "    Verrouillage  : après ${PASS_LOCKOUT} tentatives"
echo -e "    IPv6          : $([ $IPV6_DISABLE -eq 1 ] && echo 'désactivé' || echo 'activé')"

echo
ask_yn "Générer les fichiers de configuration ?" "o" CONFIRM

if [[ "$CONFIRM" != "true" ]]; then
  warn "Annulé. Aucun fichier généré."
  exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════════
section "Génération des fichiers"

INVENTORY_DIR="inventory/production"
GROUP_VARS_DIR="${INVENTORY_DIR}/group_vars"
mkdir -p "$GROUP_VARS_DIR"

# ── hosts.yml ─────────────────────────────────────────────────────────────────
info "Génération de ${INVENTORY_DIR}/hosts.yml"
cat > "${INVENTORY_DIR}/hosts.yml" << YAML
---
all:
  children:
    bastion:
      hosts:
        ${BASTION_NAME}:
          ansible_host: ${BASTION_IP}
    domain_controllers:
      hosts:
YAML

for (( i=1; i<=DC_COUNT; i++ )); do
cat >> "${INVENTORY_DIR}/hosts.yml" << YAML
        ${DC_NAMES[$((i-1))]}:
          ansible_host: ${DC_IPS[$((i-1))]}
YAML
done

cat >> "${INVENTORY_DIR}/hosts.yml" << YAML
    webservers:
      hosts:
YAML
for (( i=1; i<=WEB_COUNT; i++ )); do
cat >> "${INVENTORY_DIR}/hosts.yml" << YAML
        ${WEB_NAMES[$((i-1))]}:
          ansible_host: ${WEB_IPS[$((i-1))]}
YAML
done

cat >> "${INVENTORY_DIR}/hosts.yml" << YAML
    databases:
      hosts:
        ${DB_NAME}:
          ansible_host: ${DB_IP}
    monitoring:
      hosts:
        ${MON_NAME}:
          ansible_host: ${MON_IP}
YAML

ok "hosts.yml généré"

# ── group_vars/all.yml ────────────────────────────────────────────────────────
info "Génération de ${GROUP_VARS_DIR}/all.yml"
cat > "${GROUP_VARS_DIR}/all.yml" << YAML
---
ansible_user: ${ANSIBLE_USER}
ansible_python_interpreter: /usr/bin/python3

timezone: ${TIMEZONE}
domain_name: ${DOMAIN_NAME}

ntp_servers:
  - ${NTP1}
  - ${NTP2}

dns_servers:
  - ${DNS1}
  - ${DNS2}

syslog_server: ${MON_IP}
syslog_port: 514

# SSH
ssh_port: ${SSH_PORT}
ssh_permit_root_login: "no"
ssh_password_authentication: "no"
ssh_max_auth_tries: 3

# Mots de passe (ANSSI R31)
password_min_length: ${PASS_MIN_LEN}
password_max_days: ${PASS_MAX_DAYS}
password_min_days: ${PASS_MIN_DAYS}
password_remember: ${PASS_HISTORY}
password_warn_days: 14

# Kernel
sysctl_hardening:
  net.ipv4.ip_forward: 0
  net.ipv4.conf.all.send_redirects: 0
  net.ipv4.conf.all.accept_redirects: 0
  net.ipv4.conf.all.log_martians: 1
  net.ipv4.tcp_syncookies: 1
  net.ipv6.conf.all.disable_ipv6: ${IPV6_DISABLE}
  net.ipv6.conf.default.disable_ipv6: ${IPV6_DISABLE}
  kernel.randomize_va_space: 2
  kernel.dmesg_restrict: 1
  kernel.kptr_restrict: 2
  fs.suid_dumpable: 0

# Nginx
nginx_sites:
  - name: ${WEB_VHOST%%.*}
    server_name: ${WEB_VHOST}

# Monitoring
alertmanager_email_to: ${ALERT_EMAIL}
YAML

if [[ -n "$SLACK_WEBHOOK" ]]; then
  echo "alertmanager_slack_webhook: \"{{ vault_slack_webhook }}\"" >> "${GROUP_VARS_DIR}/all.yml"
fi

ok "all.yml généré"

# ── group_vars/domain_controllers.yml ─────────────────────────────────────────
info "Génération de ${GROUP_VARS_DIR}/domain_controllers.yml"
cat > "${GROUP_VARS_DIR}/domain_controllers.yml" << YAML
---
ansible_connection: winrm
ansible_winrm_transport: kerberos
ansible_winrm_scheme: https
ansible_winrm_server_cert_validation: validate
ansible_port: 5986

ad_domain_name: ${DOMAIN_NAME}
ad_domain_netbios: ${DOMAIN_NETBIOS}
ad_domain_functional_level: ${DC_LEVEL}
ad_forest_functional_level: ${DC_LEVEL}

ad_safe_mode_password: "{{ vault_ad_safe_mode_password }}"
ad_admin_password: "{{ vault_ad_admin_password }}"

ad_password_policy:
  min_length: ${PASS_MIN_LEN}
  max_age_days: ${PASS_MAX_DAYS}
  min_age_days: ${PASS_MIN_DAYS}
  history_count: ${PASS_HISTORY}
  complexity: true
  lockout_threshold: ${PASS_LOCKOUT}
  lockout_duration_minutes: 30
  lockout_observation_window_minutes: 30
YAML

ok "domain_controllers.yml généré"

# ── vault.yml (non chiffré — à chiffrer avec ansible-vault) ───────────────────
info "Génération de vault.yml (mots de passe)"
cat > "vault.yml" << YAML
---
# Fichier vault — chiffrer avec : ansible-vault encrypt vault.yml
vault_ad_safe_mode_password: "${VAULT_SAFEMODE_PASS}"
vault_ad_admin_password: "${VAULT_AD_ADMIN_PASS}"
vault_db_password: "${VAULT_DB_PASS}"
vault_grafana_admin_password: "${VAULT_GRAFANA_PASS}"
YAML

if [[ -n "$SLACK_WEBHOOK" ]]; then
  echo "vault_slack_webhook: \"${SLACK_WEBHOOK}\"" >> "vault.yml"
fi

ok "vault.yml généré"

# ── ansible.cfg — mise à jour clé SSH ─────────────────────────────────────────
sed -i "s|private_key_file.*|private_key_file    = ${ANSIBLE_KEY}|" ansible.cfg
sed -i "s|remote_user.*|remote_user         = ${ANSIBLE_USER}|" ansible.cfg
ok "ansible.cfg mis à jour"

# ─── Résultat final ──────────────────────────────────────────────────────────
echo
echo -e "${BOLD}${GREEN}  ✔  Configuration générée avec succès !${RESET}\n"
echo -e "  ${BOLD}Prochaines étapes :${RESET}\n"
echo -e "  ${YELLOW}1.${RESET} Chiffrer le vault :"
echo -e "     ${CYAN}ansible-vault encrypt vault.yml${RESET}\n"
echo -e "  ${YELLOW}2.${RESET} Vérifier la connectivité :"
echo -e "     ${CYAN}ansible all -m ping --ask-vault-pass${RESET}\n"
echo -e "  ${YELLOW}3.${RESET} Dry-run (Linux) :"
echo -e "     ${CYAN}ansible-playbook playbooks/site.yml --check --diff --ask-vault-pass${RESET}\n"
echo -e "  ${YELLOW}4.${RESET} Déploiement :"
echo -e "     ${CYAN}ansible-playbook playbooks/site.yml --ask-vault-pass${RESET}\n"
echo -e "  ${YELLOW}5.${RESET} Active Directory :"
echo -e "     ${CYAN}ansible-playbook playbooks/active-directory.yml --ask-vault-pass${RESET}\n"
