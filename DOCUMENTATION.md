# 🛡️ OSINT Server - Documentation complète

## Vue d'ensemble

Serveur d'investigation OSINT sécurisé pour la Police Judiciaire Fédérale - DR5-OA5.

**Infrastructure**: VPS Hetzner CX32 (4 GB RAM / 2 vCPU) - Ubuntu 22.04

---

## 🔥 Configuration Firewall Hetzner Cloud

### Accès au Firewall Hetzner

1. Connectez-vous à https://console.hetzner.cloud
2. Sélectionnez votre projet
3. Menu latéral → **Firewalls**
4. Créez ou modifiez le firewall attaché à votre VPS

---

### 📥 RÈGLES ENTRANTES (Inbound Rules)

| Protocole | Port | Source | Description |
|-----------|------|--------|-------------|
| **TCP** | 23145 | 0.0.0.0/0, ::/0 | Outline VPN (Shadowsocks) |
| **UDP** | 23145 | 0.0.0.0/0, ::/0 | Outline VPN (Shadowsocks) |
| **UDP** | 41641 | 0.0.0.0/0, ::/0 | Tailscale (WireGuard) |
| **TCP** | 22 | 0.0.0.0/0, ::/0 | SSH (backup, filtré par UFW ensuite) |

#### Configuration dans Hetzner Console:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     FIREWALL HETZNER - INBOUND RULES                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Rule 1: Outline VPN TCP                                                    │
│  ├── Protocol: TCP                                                          │
│  ├── Port: 23145                                                            │
│  └── Source: Any IPv4, Any IPv6                                             │
│                                                                             │
│  Rule 2: Outline VPN UDP                                                    │
│  ├── Protocol: UDP                                                          │
│  ├── Port: 23145                                                            │
│  └── Source: Any IPv4, Any IPv6                                             │
│                                                                             │
│  Rule 3: Tailscale                                                          │
│  ├── Protocol: UDP                                                          │
│  ├── Port: 41641                                                            │
│  └── Source: Any IPv4, Any IPv6                                             │
│                                                                             │
│  Rule 4: SSH (optionnel, backup)                                            │
│  ├── Protocol: TCP                                                          │
│  ├── Port: 22                                                               │
│  └── Source: Any (ou votre IP fixe si possible)                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

> ⚠️ **Note sécurité**: Le SSH est également protégé par UFW côté serveur (limité à Tailscale). La règle Hetzner est un backup en cas de perte Tailscale.

---

### 📤 RÈGLES SORTANTES (Outbound Rules)

| Protocole | Port | Destination | Description |
|-----------|------|-------------|-------------|
| **TCP** | 443 | 0.0.0.0/0, ::/0 | HTTPS (APIs, updates, Tor) |
| **TCP** | 80 | 0.0.0.0/0, ::/0 | HTTP (certains services) |
| **UDP** | 443 | 0.0.0.0/0, ::/0 | QUIC/HTTP3 |
| **TCP** | 9001 | 0.0.0.0/0, ::/0 | Tor ORPort |
| **TCP** | 9030 | 0.0.0.0/0, ::/0 | Tor DirPort |
| **UDP** | 53 | 0.0.0.0/0, ::/0 | DNS |
| **TCP** | 53 | 0.0.0.0/0, ::/0 | DNS over TCP |
| **TCP** | 853 | 0.0.0.0/0, ::/0 | DNS over TLS |
| **UDP** | 41641 | 0.0.0.0/0, ::/0 | Tailscale |
| **UDP** | 3478 | 0.0.0.0/0, ::/0 | Tailscale STUN |
| **ICMP** | - | 0.0.0.0/0, ::/0 | Ping (diagnostic) |

#### Configuration dans Hetzner Console:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     FIREWALL HETZNER - OUTBOUND RULES                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Rule 1: HTTPS                                                              │
│  ├── Protocol: TCP                                                          │
│  ├── Port: 443                                                              │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 2: HTTP                                                               │
│  ├── Protocol: TCP                                                          │
│  ├── Port: 80                                                               │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 3: Tor ORPort                                                         │
│  ├── Protocol: TCP                                                          │
│  ├── Port: 9001                                                             │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 4: Tor DirPort                                                        │
│  ├── Protocol: TCP                                                          │
│  ├── Port: 9030                                                             │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 5: DNS UDP                                                            │
│  ├── Protocol: UDP                                                          │
│  ├── Port: 53                                                               │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 6: DNS TCP                                                            │
│  ├── Protocol: TCP                                                          │
│  ├── Port: 53                                                               │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 7: DNS over TLS                                                       │
│  ├── Protocol: TCP                                                          │
│  ├── Port: 853                                                              │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 8: Tailscale WireGuard                                                │
│  ├── Protocol: UDP                                                          │
│  ├── Port: 41641                                                            │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 9: Tailscale STUN                                                     │
│  ├── Protocol: UDP                                                          │
│  ├── Port: 3478                                                             │
│  └── Destination: Any                                                       │
│                                                                             │
│  Rule 10: ICMP (ping)                                                       │
│  ├── Protocol: ICMP                                                         │
│  └── Destination: Any                                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

### 🔒 Option sécurité renforcée (recommandée)

Pour une sécurité maximale, vous pouvez restreindre le SSH à votre IP Tailscale uniquement **dans Hetzner** :

```
Rule SSH restrictive:
├── Protocol: TCP
├── Port: 22
└── Source: [Votre range Tailscale: 100.64.0.0/10]
```

> ⚠️ **Attention**: Si vous perdez l'accès Tailscale, vous perdez aussi SSH. Gardez toujours un accès console Hetzner disponible.

---

## 🚀 Installation

### Pré-requis

1. VPS Hetzner CX32 fraîchement installé avec Ubuntu 22.04
2. Accès root au serveur
3. Firewall Hetzner configuré (voir section précédente)
4. Compte Tailscale (https://tailscale.com)

### Étapes d'installation

```bash
# 1. Connexion SSH au serveur
ssh root@<IP_HETZNER>

# 2. Téléchargement du script
wget https://[URL_DU_SCRIPT]/install-osint-server.sh
# OU copier-coller le contenu du script

# 3. Rendre exécutable
chmod +x install-osint-server.sh

# 4. Exécution
sudo ./install-osint-server.sh
```

### Pendant l'installation

1. **Tailscale**: Le script vous demandera de vous authentifier via un lien
2. **Outline**: Notez la clé API affichée pour Outline Manager
3. **Passbolt**: Entrez les informations de l'administrateur

---

## 📊 Architecture des ports

### Vue synthétique

```
                        INTERNET
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                      FIREWALL HETZNER                                     │
│                                                                           │
│   INBOUND:  23145 (Outline), 41641 (Tailscale), 22 (SSH backup)          │
│   OUTBOUND: 80, 443, 853, 9001, 9030, 53, 41641, 3478                    │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                         UFW (Serveur)                                     │
│                                                                           │
│   PUBLIC:   23145/tcp+udp (Outline uniquement)                           │
│   TAILSCALE: 22, 3000, 3001, 5800, 7575, 8080, 8443, 9050, 9443, 9999   │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                      SERVICES DOCKER                                      │
│                                                                           │
│   Tous les services écoutent sur l'IP Tailscale (100.x.x.x)              │
│   Aucun panel exposé sur l'IP publique                                   │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
```

### Tableau récapitulatif des services

| Service | Port | Bind | Protocole | Accès |
|---------|------|------|-----------|-------|
| Outline VPN | 23145 | 0.0.0.0 | TCP+UDP | Public (seul) |
| Homarr | 7575 | Tailscale | HTTP | Admin |
| SearXNG | 8080 | Tailscale | HTTP | Admin |
| Tor Browser | 5800 | Tailscale | HTTP (noVNC) | Admin |
| Passbolt | 8443 | Tailscale | HTTPS | Admin |
| AdGuard Home | 3000 | Tailscale | HTTP | Admin |
| Uptime Kuma | 3001 | Tailscale | HTTP | Admin |
| Portainer | 9443 | Tailscale | HTTPS | Admin |
| Dozzle | 9999 | Tailscale | HTTP | Admin |
| Tor SOCKS | 9050 | Tailscale + Docker | SOCKS5 | Apps |
| SSH | 22 | Tailscale | TCP | Admin |

---

## 🔧 Utilisation quotidienne

### Mode opérationnel standard (Clearnet via Outline)

1. Lancez **Outline Client** sur votre poste
2. Connectez-vous avec la clé de l'identité souhaitée
3. Tout votre trafic passe par l'IP Hetzner

### Mode Tor (anonymisation renforcée)

#### Option A: Proxy SOCKS dans les applications

Configurez vos applications avec le proxy:
- **Host**: [IP_TAILSCALE]
- **Port**: 9050
- **Type**: SOCKS5

Exemple Firefox:
1. Paramètres → Réseau → Paramètres de connexion
2. Configuration manuelle du proxy
3. Hôte SOCKS: [IP_TAILSCALE], Port: 9050
4. SOCKS v5, cochez "DNS distant"

#### Option B: Tor Browser isolé

1. Connectez-vous via Tailscale
2. Accédez à `http://[IP_TAILSCALE]:5800`
3. Utilisez Tor Browser dans l'interface noVNC
4. Environnement complètement isolé

### Recherches OSINT (SearXNG)

1. Accédez à `http://[IP_TAILSCALE]:8080`
2. Toutes les recherches passent automatiquement par Tor
3. Aucun tracking, résultats agrégés de 70+ moteurs
4. Catégorie "onions" pour le darknet (via Ahmia)

---

## 👥 Gestion multi-identités (Outline)

### Créer une nouvelle identité

1. Ouvrez **Outline Manager** sur votre poste
2. Cliquez sur **"Ajouter une clé"**
3. Renommez la clé (ex: "Enquête Telegram Artifices 2026")
4. Partagez la clé via QR code ou lien ss://

### Révoquer une identité

1. Dans Outline Manager, trouvez la clé
2. Cliquez sur **"Supprimer"**
3. La révocation est immédiate

### Bonnes pratiques

- 1 clé par enquête/contexte
- Nommage explicite: `[Type]_[Sujet]_[Date]`
- Révoquer immédiatement les clés compromises
- Suivre la consommation par clé (anomalies = compromission potentielle)

---

## 🔐 Gestion des mots de passe (Passbolt)

### Premier accès

1. Accédez à `https://[IP_TAILSCALE]:8443`
2. Utilisez le lien d'invitation reçu par email (ou généré par le script)
3. Installez l'extension navigateur Passbolt
4. Configurez votre clé GPG

### Organisation suggérée

```
📁 OSINT Operations
├── 📁 Identités fictives
│   ├── Compte1_Telegram
│   ├── Compte2_Snapchat
│   └── Compte3_Instagram
├── 📁 Services internes
│   ├── VPN Outline Manager
│   ├── Portainer
│   └── AdGuard Home
└── 📁 Équipe
    └── Credentials partagés
```

---

## 📈 Monitoring (Uptime Kuma)

### Configuration recommandée des monitors

| Monitor | Type | URL/Host | Intervalle |
|---------|------|----------|------------|
| SearXNG | HTTP | http://searxng:8080 | 60s |
| Tor Proxy | TCP | tor-proxy:9050 | 30s |
| Tor Browser | HTTP | http://tor-browser:5800 | 60s |
| AdGuard | HTTP | http://adguard:3000 | 60s |
| Passbolt | HTTPS | https://passbolt:443 | 60s |
| Portainer | HTTPS | https://portainer:9443 | 60s |

---

## 🛠️ Maintenance

### Mise à jour des containers

```bash
/opt/osint/scripts/update.sh
```

### Backup manuel

```bash
/opt/osint/scripts/backup.sh
```

### Vérifier l'état des services

```bash
/opt/osint/scripts/status.sh
```

### Logs en temps réel

- Via Dozzle: `http://[IP_TAILSCALE]:9999`
- Via CLI: `docker logs -f [container_name]`

### Redémarrer un service

```bash
cd /opt/osint
docker compose restart [service_name]
```

### Redémarrer toute la stack

```bash
cd /opt/osint
docker compose down
docker compose up -d
```

---

## 🚨 Dépannage

### Tailscale non connecté

```bash
sudo tailscale status
sudo tailscale up
```

### Container en erreur

```bash
docker logs [container_name]
docker compose restart [service_name]
```

### Tor ne fonctionne pas

```bash
# Vérifier le circuit Tor
docker exec tor-proxy curl --socks5 localhost:9050 https://check.torproject.org/api/ip

# Redémarrer Tor
docker compose restart tor-proxy
```

### Passbolt - erreur base de données

```bash
# Vérifier MariaDB
docker logs passbolt-db

# Redémarrer la stack Passbolt
docker compose restart passbolt-db passbolt
```

### Outline non accessible

```bash
# Vérifier les containers Outline
docker ps | grep outline

# Vérifier le port
ss -tulpn | grep 23145
```

---

## 📞 Contacts & Support

- **Documentation Outline**: https://getoutline.org/
- **Documentation Tailscale**: https://tailscale.com/kb/
- **Documentation SearXNG**: https://docs.searxng.org/
- **Documentation Passbolt**: https://help.passbolt.com/

---

## 📋 Checklist post-installation

- [ ] Firewall Hetzner configuré (inbound + outbound)
- [ ] Tailscale connecté et fonctionnel
- [ ] Outline Manager configuré avec la clé API
- [ ] Au moins une clé Outline créée
- [ ] AdGuard Home configuré (upstream DNS Cloudflare)
- [ ] Compte admin Passbolt créé
- [ ] Extension Passbolt installée
- [ ] Dashboard Homarr personnalisé
- [ ] Monitors Uptime Kuma configurés
- [ ] Test de connexion Tor réussi
- [ ] Test de recherche SearXNG réussi
- [ ] Backup automatique vérifié

---

*Document généré le 2 janvier 2026 - Version 1.0*
