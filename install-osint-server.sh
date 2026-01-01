#!/bin/bash
#===============================================================================
#  OSINT SERVER - Script d'installation complet
#  VPS Hetzner CX32 - Ubuntu 22.04 - 4GB RAM / 2 vCPU
#  
#  Composants:
#  - Outline VPN (Shadowsocks)
#  - Tailscale (accès admin)
#  - Tor Proxy + Tor Browser (noVNC)
#  - SearXNG (recherche OSINT)
#  - Passbolt (gestion mots de passe)
#  - Homarr (dashboard)
#  - AdGuard Home (DNS)
#  - Uptime Kuma (monitoring)
#  - Portainer + Dozzle (gestion Docker)
#  - CrowdSec + UFW (sécurité)
#
#  Usage: sudo ./install-osint-server.sh
#===============================================================================

set -e

#-------------------------------------------------------------------------------
# VARIABLES DE CONFIGURATION
#-------------------------------------------------------------------------------
OUTLINE_PORT=23145
HOSTNAME="osint-vpn-01"
INSTALL_DIR="/opt/osint"
DOCKER_NETWORK="osint_network"
TAILSCALE_IP=""  # Sera détecté automatiquement

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------
# FONCTIONS UTILITAIRES
#-------------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root (sudo)"
        exit 1
    fi
}

wait_for_apt() {
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        log_info "Attente de la libération du lock apt..."
        sleep 5
    done
}

#-------------------------------------------------------------------------------
# PARTIE 1: PRÉPARATION SYSTÈME
#-------------------------------------------------------------------------------
prepare_system() {
    log_info "=== PARTIE 1: Préparation du système ==="
    
    # Hostname
    log_info "Configuration du hostname: $HOSTNAME"
    hostnamectl set-hostname "$HOSTNAME"
    echo "$HOSTNAME" > /etc/hostname
    
    # Mise à jour système
    log_info "Mise à jour du système..."
    wait_for_apt
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    
    # Paquets essentiels
    log_info "Installation des paquets essentiels..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl \
        wget \
        git \
        vim \
        htop \
        iotop \
        net-tools \
        dnsutils \
        jq \
        unzip \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        fail2ban \
        ufw \
        unattended-upgrades
    
    # Configuration unattended-upgrades
    log_info "Configuration des mises à jour automatiques de sécurité..."
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    # Créer le répertoire d'installation
    mkdir -p "$INSTALL_DIR"/{configs,data,scripts,backups}
    
    log_success "Système préparé avec succès"
}

#-------------------------------------------------------------------------------
# PARTIE 2: INSTALLATION DOCKER
#-------------------------------------------------------------------------------
install_docker() {
    log_info "=== PARTIE 2: Installation de Docker ==="
    
    if command -v docker &> /dev/null; then
        log_warning "Docker déjà installé, mise à jour..."
    else
        log_info "Installation de Docker..."
        
        # Ajout du repo Docker officiel
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        wait_for_apt
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    
    # Démarrer et activer Docker
    systemctl enable docker
    systemctl start docker
    
    # Créer le réseau Docker
    log_info "Création du réseau Docker: $DOCKER_NETWORK"
    docker network create "$DOCKER_NETWORK" 2>/dev/null || log_warning "Réseau déjà existant"
    
    log_success "Docker installé et configuré"
}

#-------------------------------------------------------------------------------
# PARTIE 3: INSTALLATION TAILSCALE
#-------------------------------------------------------------------------------
install_tailscale() {
    log_info "=== PARTIE 3: Installation de Tailscale ==="
    
    if command -v tailscale &> /dev/null; then
        log_warning "Tailscale déjà installé"
    else
        log_info "Installation de Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    # Démarrer Tailscale
    systemctl enable tailscaled
    systemctl start tailscaled
    
    log_warning "=== ACTION REQUISE ==="
    echo ""
    echo "Exécutez la commande suivante pour connecter Tailscale:"
    echo ""
    echo "    sudo tailscale up"
    echo ""
    echo "Suivez le lien affiché pour authentifier le serveur."
    echo ""
    read -p "Appuyez sur Entrée une fois Tailscale connecté..."
    
    # Récupérer l'IP Tailscale
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
    
    if [[ -z "$TAILSCALE_IP" ]]; then
        log_error "Impossible de récupérer l'IP Tailscale. Vérifiez la connexion."
        read -p "Entrez manuellement l'IP Tailscale (100.x.x.x): " TAILSCALE_IP
    fi
    
    log_success "Tailscale connecté: $TAILSCALE_IP"
    
    # Sauvegarder l'IP pour utilisation ultérieure
    echo "$TAILSCALE_IP" > "$INSTALL_DIR/tailscale_ip.txt"
}

#-------------------------------------------------------------------------------
# PARTIE 4: CONFIGURATION FIREWALL (UFW)
#-------------------------------------------------------------------------------
configure_firewall() {
    log_info "=== PARTIE 4: Configuration du firewall UFW ==="
    
    # Reset UFW
    ufw --force reset
    
    # Politique par défaut
    ufw default deny incoming
    ufw default allow outgoing
    
    # SSH uniquement depuis Tailscale
    ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH via Tailscale'
    
    # Outline VPN (seul port public)
    ufw allow ${OUTLINE_PORT}/tcp comment 'Outline VPN TCP'
    ufw allow ${OUTLINE_PORT}/udp comment 'Outline VPN UDP'
    
    # Activer UFW
    ufw --force enable
    
    log_success "Firewall UFW configuré"
    ufw status verbose
}

#-------------------------------------------------------------------------------
# PARTIE 5: INSTALLATION CROWDSEC
#-------------------------------------------------------------------------------
install_crowdsec() {
    log_info "=== PARTIE 5: Installation de CrowdSec ==="
    
    # Installation CrowdSec
    curl -s https://install.crowdsec.net | bash
    
    # Installation du bouncer firewall
    apt-get install -y crowdsec-firewall-bouncer-iptables
    
    # Collections pour la protection
    cscli collections install crowdsecurity/linux
    cscli collections install crowdsecurity/sshd
    cscli collections install crowdsecurity/nginx  # Au cas où
    
    # Redémarrer CrowdSec
    systemctl restart crowdsec
    systemctl enable crowdsec
    
    log_success "CrowdSec installé et configuré"
}

#-------------------------------------------------------------------------------
# PARTIE 6: INSTALLATION OUTLINE VPN
#-------------------------------------------------------------------------------
install_outline() {
    log_info "=== PARTIE 6: Installation d'Outline VPN ==="
    
    log_info "Téléchargement du script d'installation Outline..."
    
    # Créer le répertoire pour Outline
    mkdir -p "$INSTALL_DIR/outline"
    cd "$INSTALL_DIR/outline"
    
    # Télécharger et exécuter le script d'installation avec le port personnalisé
    # Le script Outline génère automatiquement les clés d'accès
    bash -c "$(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh)" -- --api-port 8443 --keys-port ${OUTLINE_PORT}
    
    log_success "Outline VPN installé sur le port ${OUTLINE_PORT}"
    log_warning "=== IMPORTANT ==="
    echo ""
    echo "Copiez la clé d'accès affichée ci-dessus (apiUrl)."
    echo "Vous en aurez besoin pour configurer Outline Manager sur votre poste."
    echo ""
    echo "Téléchargez Outline Manager: https://getoutline.org/get-started/#step-1"
    echo ""
    
    read -p "Appuyez sur Entrée pour continuer..."
}

#-------------------------------------------------------------------------------
# PARTIE 7: DÉPLOIEMENT STACK DOCKER
#-------------------------------------------------------------------------------
deploy_docker_stack() {
    log_info "=== PARTIE 7: Déploiement de la stack Docker ==="
    
    TAILSCALE_IP=$(cat "$INSTALL_DIR/tailscale_ip.txt")
    
    # Créer les répertoires de données
    mkdir -p "$INSTALL_DIR/data"/{portainer,adguard/{work,conf},searxng,tor-browser,uptime-kuma,dozzle,homarr/{configs,icons,data},passbolt/{gpg,jwt}}
    mkdir -p "$INSTALL_DIR/data/passbolt/database"
    
    # Générer les secrets Passbolt
    PASSBOLT_JWT_KEY=$(openssl rand -base64 32)
    PASSBOLT_SECURITY_SALT=$(openssl rand -base64 32)
    MARIADB_ROOT_PASSWORD=$(openssl rand -base64 24)
    MARIADB_PASSWORD=$(openssl rand -base64 24)
    
    # Sauvegarder les credentials
    cat > "$INSTALL_DIR/credentials.txt" << EOF
#===============================================================================
# CREDENTIALS OSINT SERVER - CONFIDENTIEL
# Généré le: $(date)
#===============================================================================

# MariaDB (Passbolt)
MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD
MARIADB_PASSWORD=$MARIADB_PASSWORD

# Passbolt
PASSBOLT_JWT_KEY=$PASSBOLT_JWT_KEY
PASSBOLT_SECURITY_SALT=$PASSBOLT_SECURITY_SALT

# Tailscale IP
TAILSCALE_IP=$TAILSCALE_IP

# URLs d'accès (via Tailscale uniquement)
Homarr:      http://$TAILSCALE_IP:7575
Portainer:   https://$TAILSCALE_IP:9443
Passbolt:    https://$TAILSCALE_IP:8443
AdGuard:     http://$TAILSCALE_IP:3000
SearXNG:     http://$TAILSCALE_IP:8080
Tor Browser: http://$TAILSCALE_IP:5800
Uptime Kuma: http://$TAILSCALE_IP:3001
Dozzle:      http://$TAILSCALE_IP:9999
EOF
    chmod 600 "$INSTALL_DIR/credentials.txt"
    
    # Créer le docker-compose.yml
    log_info "Création du fichier docker-compose.yml..."
    
    cat > "$INSTALL_DIR/docker-compose.yml" << EOF
version: "3.8"

networks:
  osint_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

services:
  #=============================================================================
  # TOR PROXY - SOCKS5 pour anonymisation
  #=============================================================================
  tor-proxy:
    image: dperson/torproxy:latest
    container_name: tor-proxy
    restart: unless-stopped
    networks:
      osint_network:
        ipv4_address: 172.20.0.10
    environment:
      - TOR_NewCircuitPeriod=120
      - TOR_MaxCircuitDirtiness=600
    ports:
      - "${TAILSCALE_IP}:9050:9050"  # SOCKS5 accessible via Tailscale
    healthcheck:
      test: ["CMD", "curl", "--socks5", "localhost:9050", "-s", "https://check.torproject.org/api/ip"]
      interval: 60s
      timeout: 15s
      retries: 3

  #=============================================================================
  # TOR BROWSER - Navigateur isolé via noVNC
  #=============================================================================
  tor-browser:
    image: domistyle/tor-browser:latest
    container_name: tor-browser
    restart: unless-stopped
    networks:
      - osint_network
    environment:
      - DISPLAY_WIDTH=1920
      - DISPLAY_HEIGHT=1080
      - PUID=1000
      - PGID=1000
    volumes:
      - ${INSTALL_DIR}/data/tor-browser:/config
    ports:
      - "${TAILSCALE_IP}:5800:5800"
    shm_size: '2gb'

  #=============================================================================
  # ADGUARD HOME - DNS sécurisé
  #=============================================================================
  adguard:
    image: adguard/adguardhome:latest
    container_name: adguard
    restart: unless-stopped
    networks:
      osint_network:
        ipv4_address: 172.20.0.20
    volumes:
      - ${INSTALL_DIR}/data/adguard/work:/opt/adguardhome/work
      - ${INSTALL_DIR}/data/adguard/conf:/opt/adguardhome/conf
    ports:
      - "${TAILSCALE_IP}:3000:3000"   # Interface web
      - "172.20.0.20:53:53/tcp"        # DNS TCP interne
      - "172.20.0.20:53:53/udp"        # DNS UDP interne

  #=============================================================================
  # SEARXNG - Méta-moteur de recherche OSINT
  #=============================================================================
  searxng:
    image: searxng/searxng:latest
    container_name: searxng
    restart: unless-stopped
    networks:
      - osint_network
    volumes:
      - ${INSTALL_DIR}/data/searxng:/etc/searxng
      - ${INSTALL_DIR}/configs/searxng/settings.yml:/etc/searxng/settings.yml:ro
    environment:
      - SEARXNG_BASE_URL=http://${TAILSCALE_IP}:8080/
      - SEARXNG_SECRET=\$(openssl rand -hex 32)
    ports:
      - "${TAILSCALE_IP}:8080:8080"
    depends_on:
      - tor-proxy
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETGID
      - SETUID

  #=============================================================================
  # PASSBOLT - Gestionnaire de mots de passe
  #=============================================================================
  passbolt-db:
    image: mariadb:10.11
    container_name: passbolt-db
    restart: unless-stopped
    networks:
      - osint_network
    environment:
      - MYSQL_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
      - MYSQL_DATABASE=passbolt
      - MYSQL_USER=passbolt
      - MYSQL_PASSWORD=${MARIADB_PASSWORD}
    volumes:
      - ${INSTALL_DIR}/data/passbolt/database:/var/lib/mysql
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci

  passbolt:
    image: passbolt/passbolt:latest-ce
    container_name: passbolt
    restart: unless-stopped
    networks:
      - osint_network
    environment:
      - APP_FULL_BASE_URL=https://${TAILSCALE_IP}:8443
      - DATASOURCES_DEFAULT_HOST=passbolt-db
      - DATASOURCES_DEFAULT_USERNAME=passbolt
      - DATASOURCES_DEFAULT_PASSWORD=${MARIADB_PASSWORD}
      - DATASOURCES_DEFAULT_DATABASE=passbolt
      - EMAIL_TRANSPORT_DEFAULT_CLASS_NAME=Smtp
      - EMAIL_DEFAULT_FROM=no-reply@osint.local
      - PASSBOLT_KEY_LENGTH=4096
      - PASSBOLT_SUBKEY_LENGTH=4096
      - SECURITY_SALT=${PASSBOLT_SECURITY_SALT}
    volumes:
      - ${INSTALL_DIR}/data/passbolt/gpg:/etc/passbolt/gpg
      - ${INSTALL_DIR}/data/passbolt/jwt:/etc/passbolt/jwt
    ports:
      - "${TAILSCALE_IP}:8443:443"
    depends_on:
      - passbolt-db
    command: >
      bash -c "/usr/bin/wait-for.sh -t 0 passbolt-db:3306 -- /docker-entrypoint.sh"

  #=============================================================================
  # HOMARR - Dashboard
  #=============================================================================
  homarr:
    image: ghcr.io/ajnart/homarr:latest
    container_name: homarr
    restart: unless-stopped
    networks:
      - osint_network
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${INSTALL_DIR}/data/homarr/configs:/app/data/configs
      - ${INSTALL_DIR}/data/homarr/icons:/app/public/icons
      - ${INSTALL_DIR}/data/homarr/data:/data
    environment:
      - TZ=Europe/Brussels
    ports:
      - "${TAILSCALE_IP}:7575:7575"

  #=============================================================================
  # UPTIME KUMA - Monitoring
  #=============================================================================
  uptime-kuma:
    image: louislam/uptime-kuma:latest
    container_name: uptime-kuma
    restart: unless-stopped
    networks:
      - osint_network
    volumes:
      - ${INSTALL_DIR}/data/uptime-kuma:/app/data
    ports:
      - "${TAILSCALE_IP}:3001:3001"

  #=============================================================================
  # PORTAINER - Gestion Docker
  #=============================================================================
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    networks:
      - osint_network
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${INSTALL_DIR}/data/portainer:/data
    ports:
      - "${TAILSCALE_IP}:9443:9443"

  #=============================================================================
  # DOZZLE - Logs en temps réel
  #=============================================================================
  dozzle:
    image: amir20/dozzle:latest
    container_name: dozzle
    restart: unless-stopped
    networks:
      - osint_network
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      - DOZZLE_LEVEL=info
      - DOZZLE_TAILSIZE=300
    ports:
      - "${TAILSCALE_IP}:9999:8080"
EOF

    log_success "docker-compose.yml créé"
}

#-------------------------------------------------------------------------------
# PARTIE 8: CONFIGURATION SEARXNG OSINT
#-------------------------------------------------------------------------------
configure_searxng() {
    log_info "=== PARTIE 8: Configuration SearXNG optimisée OSINT ==="
    
    mkdir -p "$INSTALL_DIR/configs/searxng"
    
    cat > "$INSTALL_DIR/configs/searxng/settings.yml" << 'EOF'
#===============================================================================
# SEARXNG - Configuration optimisée OSINT
# Police Judiciaire Fédérale - DR5-OA5
#===============================================================================

use_default_settings: true

general:
  debug: false
  instance_name: "OSINT Search"
  privacypolicy_url: false
  donation_url: false
  contact_url: false
  enable_metrics: false

search:
  safe_search: 0                    # Pas de filtre SafeSearch
  autocomplete: ""                  # Désactivé pour discrétion
  default_lang: "all"               # Toutes les langues
  ban_time_on_fail: 5
  max_ban_time_on_fail: 120
  formats:
    - html
    - json                          # API pour automation future

server:
  port: 8080
  bind_address: "0.0.0.0"
  secret_key: "CHANGE_ME_RANDOM_SECRET_KEY_HERE"
  base_url: false
  image_proxy: true                 # Proxy images (masque IP client)
  http_protocol_version: "1.1"
  method: "GET"
  default_http_headers:
    X-Content-Type-Options: nosniff
    X-Download-Options: noopen
    X-Robots-Tag: noindex, nofollow
    Referrer-Policy: no-referrer

ui:
  static_use_hash: true
  default_locale: "fr"
  query_in_title: true
  infinite_scroll: true
  center_alignment: false
  default_theme: simple
  theme_args:
    simple_style: dark

# Routing via Tor pour l'anonymisation
outgoing:
  request_timeout: 10.0             # Timeout plus long pour Tor
  max_request_timeout: 30.0
  useragent_suffix: ""              # Pas de fingerprint
  pool_connections: 100
  pool_maxsize: 20
  enable_http2: false
  
  # Proxy Tor SOCKS5
  proxies:
    all://:
      - socks5h://tor-proxy:9050
  
  using_tor_proxy: true
  extra_proxy_timeout: 20.0

# Catégories affichées en onglets
categories_as_tabs:
  general:
  images:
  videos:
  news:
  social media:
  onions:                           # Recherche darknet

# Configuration des moteurs
engines:
  # === MOTEURS GÉNÉRAUX ===
  - name: google
    disabled: false
    weight: 1.2
    
  - name: duckduckgo
    disabled: false
    weight: 1.0
    
  - name: bing
    disabled: false
    weight: 0.8
    
  - name: brave
    disabled: false
    weight: 1.0
    
  - name: startpage
    disabled: false
    weight: 0.9
    
  - name: qwant
    disabled: false
    weight: 0.7
    
  # === MOTEURS DARKNET ===
  - name: ahmia
    engine: ahmia
    categories: onions
    shortcut: ah
    disabled: false
    timeout: 15
    
  # === ARCHIVES WEB ===
  - name: archive is
    disabled: false
    weight: 1.0
    
  - name: internet archive
    disabled: false
    shortcut: ia
    
  - name: wayback machine
    disabled: false
    
  # === SOCIAL MEDIA ===
  - name: reddit
    disabled: false
    weight: 1.0
    
  - name: lemmy
    disabled: false
    
  # === IMAGES ===
  - name: google images
    disabled: false
    safesearch: 0
    
  - name: bing images
    disabled: false
    safesearch: 0
    
  - name: duckduckgo images
    disabled: false
    safesearch: 0
    
  # === VIDÉOS ===
  - name: youtube
    disabled: false
    
  - name: dailymotion
    disabled: false
    
  - name: vimeo
    disabled: false
    
  # === NEWS ===
  - name: google news
    disabled: false
    
  - name: bing news
    disabled: false
    
  # === PEOPLE SEARCH ===
  - name: wikidata
    disabled: false
    weight: 1.2
    
  - name: wikipedia
    disabled: false
    weight: 1.1
    
  # === IT / TECH ===
  - name: github
    disabled: false
    
  - name: gitlab
    disabled: false
    
  - name: stackoverflow
    disabled: false
    
  # === FICHIERS ===
  - name: z-library
    disabled: true                  # Désactivé, légalité variable
    
  # === MOTEURS SPÉCIALISÉS ===
  - name: currency
    disabled: false
    
  - name: dictzone
    disabled: false
    
  - name: openstreetmap
    disabled: false
EOF

    # Générer une clé secrète aléatoire
    SECRET_KEY=$(openssl rand -hex 32)
    sed -i "s/CHANGE_ME_RANDOM_SECRET_KEY_HERE/$SECRET_KEY/" "$INSTALL_DIR/configs/searxng/settings.yml"
    
    # Permissions
    chmod 644 "$INSTALL_DIR/configs/searxng/settings.yml"
    
    log_success "Configuration SearXNG créée"
}

#-------------------------------------------------------------------------------
# PARTIE 9: DÉMARRAGE DES SERVICES
#-------------------------------------------------------------------------------
start_services() {
    log_info "=== PARTIE 9: Démarrage des services Docker ==="
    
    cd "$INSTALL_DIR"
    
    # Exporter les variables d'environnement
    export INSTALL_DIR
    export TAILSCALE_IP=$(cat "$INSTALL_DIR/tailscale_ip.txt")
    
    # Charger les credentials
    source <(grep -E '^[A-Z_]+=.+$' "$INSTALL_DIR/credentials.txt")
    export MARIADB_ROOT_PASSWORD
    export MARIADB_PASSWORD
    export PASSBOLT_SECURITY_SALT
    
    # Créer le fichier .env
    cat > "$INSTALL_DIR/.env" << EOF
INSTALL_DIR=${INSTALL_DIR}
TAILSCALE_IP=${TAILSCALE_IP}
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD}
MARIADB_PASSWORD=${MARIADB_PASSWORD}
PASSBOLT_SECURITY_SALT=${PASSBOLT_SECURITY_SALT}
EOF
    chmod 600 "$INSTALL_DIR/.env"
    
    # Démarrer les services
    log_info "Démarrage des containers..."
    docker compose up -d
    
    # Attendre le démarrage
    log_info "Attente du démarrage des services (60 secondes)..."
    sleep 60
    
    # Vérifier l'état
    docker compose ps
    
    log_success "Services Docker démarrés"
}

#-------------------------------------------------------------------------------
# PARTIE 10: CONFIGURATION POST-INSTALLATION
#-------------------------------------------------------------------------------
post_install() {
    log_info "=== PARTIE 10: Configuration post-installation ==="
    
    TAILSCALE_IP=$(cat "$INSTALL_DIR/tailscale_ip.txt")
    
    # Créer le premier utilisateur Passbolt
    log_info "Création de l'utilisateur admin Passbolt..."
    echo ""
    read -p "Email administrateur Passbolt: " ADMIN_EMAIL
    read -p "Prénom: " ADMIN_FIRSTNAME
    read -p "Nom: " ADMIN_LASTNAME
    
    docker exec passbolt su -m -c "/usr/share/php/passbolt/bin/cake passbolt register_user -u $ADMIN_EMAIL -f $ADMIN_FIRSTNAME -l $ADMIN_LASTNAME -r admin" -s /bin/sh www-data || log_warning "Création utilisateur - vérifiez manuellement"
    
    # Scripts utilitaires
    log_info "Création des scripts utilitaires..."
    
    # Script de backup
    cat > "$INSTALL_DIR/scripts/backup.sh" << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/osint/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

# Backup des configs
tar -czf "$BACKUP_DIR/configs_$DATE.tar.gz" /opt/osint/configs

# Backup des données critiques
tar -czf "$BACKUP_DIR/data_$DATE.tar.gz" \
    /opt/osint/data/adguard \
    /opt/osint/data/searxng \
    /opt/osint/data/uptime-kuma \
    /opt/osint/data/homarr

# Backup Passbolt (base de données)
docker exec passbolt-db mysqldump -u root -p"$MARIADB_ROOT_PASSWORD" passbolt > "$BACKUP_DIR/passbolt_db_$DATE.sql"

# Nettoyer les vieux backups (garder 7 jours)
find "$BACKUP_DIR" -type f -mtime +7 -delete

echo "Backup terminé: $BACKUP_DIR"
EOF
    chmod +x "$INSTALL_DIR/scripts/backup.sh"
    
    # Script de mise à jour
    cat > "$INSTALL_DIR/scripts/update.sh" << 'EOF'
#!/bin/bash
cd /opt/osint
docker compose pull
docker compose up -d
docker image prune -f
echo "Mise à jour terminée"
EOF
    chmod +x "$INSTALL_DIR/scripts/update.sh"
    
    # Script de statut
    cat > "$INSTALL_DIR/scripts/status.sh" << 'EOF'
#!/bin/bash
echo "=== État des services OSINT ==="
docker compose -f /opt/osint/docker-compose.yml ps
echo ""
echo "=== Utilisation ressources ==="
docker stats --no-stream
echo ""
echo "=== Espace disque ==="
df -h /opt/osint
EOF
    chmod +x "$INSTALL_DIR/scripts/status.sh"
    
    # Cron pour backup quotidien
    (crontab -l 2>/dev/null; echo "0 3 * * * /opt/osint/scripts/backup.sh >> /var/log/osint-backup.log 2>&1") | crontab -
    
    log_success "Configuration post-installation terminée"
}

#-------------------------------------------------------------------------------
# PARTIE 11: RÉSUMÉ FINAL
#-------------------------------------------------------------------------------
show_summary() {
    TAILSCALE_IP=$(cat "$INSTALL_DIR/tailscale_ip.txt")
    
    clear
    echo ""
    echo "==============================================================================="
    echo "     🛡️  INSTALLATION OSINT SERVER TERMINÉE"
    echo "==============================================================================="
    echo ""
    echo "📍 IP Tailscale: $TAILSCALE_IP"
    echo "📍 Port Outline VPN: $OUTLINE_PORT"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "  ACCÈS AUX SERVICES (via Tailscale uniquement)"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo "  🏠 Dashboard Homarr     : http://$TAILSCALE_IP:7575"
    echo "  🔍 SearXNG (OSINT)      : http://$TAILSCALE_IP:8080"
    echo "  🧅 Tor Browser          : http://$TAILSCALE_IP:5800"
    echo "  🔐 Passbolt             : https://$TAILSCALE_IP:8443"
    echo "  🛡️  AdGuard Home         : http://$TAILSCALE_IP:3000"
    echo "  📊 Uptime Kuma          : http://$TAILSCALE_IP:3001"
    echo "  🐳 Portainer            : https://$TAILSCALE_IP:9443"
    echo "  📋 Dozzle (logs)        : http://$TAILSCALE_IP:9999"
    echo "  🧅 Tor SOCKS Proxy      : $TAILSCALE_IP:9050"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "  FICHIERS IMPORTANTS"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo "  📁 Répertoire principal : /opt/osint"
    echo "  🔑 Credentials          : /opt/osint/credentials.txt"
    echo "  📝 Docker Compose       : /opt/osint/docker-compose.yml"
    echo "  ⚙️  Config SearXNG       : /opt/osint/configs/searxng/settings.yml"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "  SCRIPTS UTILITAIRES"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo "  /opt/osint/scripts/backup.sh   - Backup quotidien"
    echo "  /opt/osint/scripts/update.sh   - Mise à jour containers"
    echo "  /opt/osint/scripts/status.sh   - État des services"
    echo ""
    echo "-------------------------------------------------------------------------------"
    echo "  PROCHAINES ÉTAPES"
    echo "-------------------------------------------------------------------------------"
    echo ""
    echo "  1. Configurer Outline Manager avec la clé API affichée lors de l'installation"
    echo "  2. Accéder à AdGuard Home ($TAILSCALE_IP:3000) pour finaliser le setup DNS"
    echo "  3. Créer votre compte Passbolt avec le lien reçu par email (si configuré)"
    echo "  4. Personnaliser le dashboard Homarr"
    echo "  5. Configurer les monitors dans Uptime Kuma"
    echo ""
    echo "==============================================================================="
    echo "  ⚠️  RAPPEL SÉCURITÉ: Tous les panels sont accessibles UNIQUEMENT via Tailscale"
    echo "==============================================================================="
    echo ""
}

#-------------------------------------------------------------------------------
# MAIN
#-------------------------------------------------------------------------------
main() {
    clear
    echo ""
    echo "==============================================================================="
    echo "     🛡️  INSTALLATION OSINT SERVER - VPS Hetzner"
    echo "==============================================================================="
    echo ""
    echo "Ce script va installer et configurer:"
    echo "  • Outline VPN (Shadowsocks)"
    echo "  • Tailscale (accès admin sécurisé)"
    echo "  • Tor Proxy + Tor Browser"
    echo "  • SearXNG (recherche OSINT)"
    echo "  • Passbolt (mots de passe)"
    echo "  • Homarr (dashboard)"
    echo "  • AdGuard Home (DNS)"
    echo "  • Uptime Kuma + Portainer + Dozzle"
    echo "  • UFW + CrowdSec (sécurité)"
    echo ""
    echo "Durée estimée: 15-20 minutes"
    echo ""
    
    read -p "Continuer l'installation ? (o/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Oo]$ ]]; then
        exit 0
    fi
    
    check_root
    
    prepare_system
    install_docker
    install_tailscale
    configure_firewall
    install_crowdsec
    install_outline
    configure_searxng
    deploy_docker_stack
    start_services
    post_install
    show_summary
}

# Exécution
main "$@"
