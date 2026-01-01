# 🔥 PORTS HETZNER CLOUD FIREWALL - Référence rapide

## Configuration dans Hetzner Console

Accès: https://console.hetzner.cloud → Projet → Firewalls

---

## 📥 RÈGLES ENTRANTES (Inbound)

```
┌──────────────┬───────────┬─────────────────────┬────────────────────────────┐
│ PROTOCOLE    │ PORT      │ SOURCE              │ DESCRIPTION                │
├──────────────┼───────────┼─────────────────────┼────────────────────────────┤
│ TCP          │ 23145     │ Any IPv4, Any IPv6  │ Outline VPN (Shadowsocks)  │
│ UDP          │ 23145     │ Any IPv4, Any IPv6  │ Outline VPN (Shadowsocks)  │
│ UDP          │ 41641     │ Any IPv4, Any IPv6  │ Tailscale WireGuard        │
│ TCP          │ 22        │ Any IPv4, Any IPv6  │ SSH (backup accès)         │
└──────────────┴───────────┴─────────────────────┴────────────────────────────┘
```

### Copier-coller pour Hetzner:

**Rule 1 - Outline TCP:**
- Protocol: `TCP`
- Port: `23145`
- Source: `Any IPv4`, `Any IPv6`

**Rule 2 - Outline UDP:**
- Protocol: `UDP`
- Port: `23145`
- Source: `Any IPv4`, `Any IPv6`

**Rule 3 - Tailscale:**
- Protocol: `UDP`
- Port: `41641`
- Source: `Any IPv4`, `Any IPv6`

**Rule 4 - SSH:**
- Protocol: `TCP`
- Port: `22`
- Source: `Any IPv4`, `Any IPv6`

---

## 📤 RÈGLES SORTANTES (Outbound)

```
┌──────────────┬───────────┬─────────────────────┬────────────────────────────┐
│ PROTOCOLE    │ PORT      │ DESTINATION         │ DESCRIPTION                │
├──────────────┼───────────┼─────────────────────┼────────────────────────────┤
│ TCP          │ 443       │ Any                 │ HTTPS (APIs, Tor, updates) │
│ TCP          │ 80        │ Any                 │ HTTP                       │
│ TCP          │ 9001      │ Any                 │ Tor ORPort                 │
│ TCP          │ 9030      │ Any                 │ Tor DirPort                │
│ UDP          │ 53        │ Any                 │ DNS                        │
│ TCP          │ 53        │ Any                 │ DNS over TCP               │
│ TCP          │ 853       │ Any                 │ DNS over TLS (DoT)         │
│ UDP          │ 41641     │ Any                 │ Tailscale WireGuard        │
│ UDP          │ 3478      │ Any                 │ Tailscale STUN             │
│ ICMP         │ -         │ Any                 │ Ping                       │
└──────────────┴───────────┴─────────────────────┴────────────────────────────┘
```

### Copier-coller pour Hetzner:

**Rule 1 - HTTPS:**
- Protocol: `TCP`
- Port: `443`
- Destination: `Any`

**Rule 2 - HTTP:**
- Protocol: `TCP`
- Port: `80`
- Destination: `Any`

**Rule 3 - Tor ORPort:**
- Protocol: `TCP`
- Port: `9001`
- Destination: `Any`

**Rule 4 - Tor DirPort:**
- Protocol: `TCP`
- Port: `9030`
- Destination: `Any`

**Rule 5 - DNS UDP:**
- Protocol: `UDP`
- Port: `53`
- Destination: `Any`

**Rule 6 - DNS TCP:**
- Protocol: `TCP`
- Port: `53`
- Destination: `Any`

**Rule 7 - DoT:**
- Protocol: `TCP`
- Port: `853`
- Destination: `Any`

**Rule 8 - Tailscale:**
- Protocol: `UDP`
- Port: `41641`
- Destination: `Any`

**Rule 9 - STUN:**
- Protocol: `UDP`
- Port: `3478`
- Destination: `Any`

**Rule 10 - ICMP:**
- Protocol: `ICMP`
- Destination: `Any`

---

## ⚠️ IMPORTANT

1. **Créez le firewall AVANT d'exécuter le script d'installation**
2. **Attachez le firewall au VPS** après sa création
3. Le port SSH (22) est aussi protégé par UFW côté serveur
4. Seul le port Outline (23145) est réellement exposé publiquement

---

## 🔒 Option sécurité maximale

Pour restreindre SSH à Tailscale uniquement dans Hetzner:

```
Inbound Rule SSH restrictive:
├── Protocol: TCP
├── Port: 22
└── Source: 100.64.0.0/10 (range Tailscale)
```

⚠️ Si vous perdez Tailscale = vous perdez SSH. Gardez l'accès console Hetzner!
