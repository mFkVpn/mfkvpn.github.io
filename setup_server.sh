#!/usr/bin/env bash
# ==============================================================================
# mFkVpN - Hetzner / Debian / Ubuntu 5-10 Cihazlık WireGuard Sunucu Kurulum Betiği
# 25 Temel Maddeye Uygun Güçlendirilmiş & Sıfır Günlük (Zero-Logs) Kurulum
# ==============================================================================

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "[-] Bu betik root yetkisiyle çalıştırılmalıdır (sudo ./setup_server.sh)." >&2
  exit 1
fi

echo "=========================================================="
echo "  mFkVpN - Güvenli WireGuard Düğüm Kurulumu Başlatılıyor  "
echo "=========================================================="

WG_IF="wg0"
WG_PORT=51820
WG_NET="10.13.13.1/24"
WG_SUBNET="10.13.13.0/24"
PEERS_FILE="/etc/wireguard/peers.map"

# 1. Sistem Güncellemeleri ve Paketler (Madde 1, 4)
echo "[+] Sistem paketleri güncelleniyor..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wireguard wireguard-tools ufw fail2ban unattended-upgrades curl iptables qrencode

# 2. Çekirdek Güçlendirmesi & IP Yönlendirme (Madde 5, 10)
echo "[+] Çekirdek ağ parametreleri uygulanıyor (Forwarding ON, IPv6 Leak Koruma)..."
cat > /etc/sysctl.d/99-mfkvpn.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
# IPv6 sızıntılarını önlemek için güvenli kapatma (Madde 10)
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
sysctl --system > /dev/null

# 3. Sıfır Günlük (Zero-Logs) Yapılandırması (Madde 15)
echo "[+] RAM-Only (Sıfır Günlük) journald yapılandırması..."
mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/zero-logs.conf << 'EOF'
[Journal]
Storage=volatile
SystemMaxUse=16M
RuntimeMaxUse=16M
EOF
systemctl restart systemd-journald

# 4. Aktif İnternet Ağ Arayüzünü Tespit Et
PUB_NIC=$(ip route show default | awk '{print $5}' | head -n1)
if [ -z "$PUB_NIC" ]; then
  PUB_NIC="eth0"
fi
echo "[+] Aktif çıkış arayüzü: $PUB_NIC"

# 5. WireGuard Sunucu Anahtarlarını Üret (Madde 6, 7)
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
if [ ! -f /etc/wireguard/server.key ]; then
  echo "[+] Sunucu WireGuard anahtarları oluşturuluyor..."
  wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
  chmod 600 /etc/wireguard/server.key
fi

SERVER_PRIV=$(cat /etc/wireguard/server.key)
SERVER_PUB=$(cat /etc/wireguard/server.pub)

# 6. WireGuard wg0.conf Yapılandırması (Madde 9, 11)
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = $WG_NET
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
MTU = 1360

# NAT Masquerade kuralları
PostUp = iptables -A FORWARD -i $WG_IF -j ACCEPT; iptables -t nat -A POSTROUTING -o $PUB_NIC -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_IF -j ACCEPT; iptables -t nat -D POSTROUTING -o $PUB_NIC -j MASQUERADE
EOF
chmod 600 /etc/wireguard/wg0.conf
touch "$PEERS_FILE"
chmod 600 "$PEERS_FILE"

# 7. Güvenlik Duvarı (UFW) Yapılandırması (Madde 3)
echo "[+] UFW Güvenlik Duvarı kural seti ayarlanıyor..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow ${WG_PORT}/udp comment 'WireGuard VPN'
# UFW NAT / Routed Trafik izni
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
echo "y" | ufw enable || true

# 8. vpnctl Yönetim Betiği Kurulumu (Madde 19 - GitOps desteği)
echo "[+] /usr/local/bin/vpnctl yönetim betiği kuruluyor..."
cat > /usr/local/bin/vpnctl << 'CTL'
#!/usr/bin/env bash
set -euo pipefail

PEERS_FILE="/etc/wireguard/peers.map"
WG_IF="wg0"

case "${1:-}" in
  start)
    systemctl start wg-quick@$WG_IF
    echo "state=running started=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    ;;
  stop)
    systemctl stop wg-quick@$WG_IF
    echo "state=exited"
    ;;
  restart)
    systemctl restart wg-quick@$WG_IF
    echo "state=running started=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    ;;
  status)
    if systemctl is-active --quiet wg-quick@$WG_IF; then
      echo "state=running"
    else
      echo "state=exited"
    fi
    echo -n "peers="
    wg show $WG_IF peers 2>/dev/null | wc -l || echo 0
    ;;
  list-peers)
    if [ -f "$PEERS_FILE" ]; then
      while IFS='|' read -r name pub ip; do
        [ -z "$name" ] && continue
        DUMP=$(wg show $WG_IF dump 2>/dev/null | grep -F "$pub" | head -n1 || true)
        if [ -n "$DUMP" ]; then
          HS=$(echo "$DUMP" | awk '{print $5}')
          RX=$(echo "$DUMP" | awk '{print $6}')
          TX=$(echo "$DUMP" | awk '{print $7}')
        else
          HS=0; RX=0; TX=0
        fi
        echo "peer=$name|$pub|$ip|$HS|$RX|$TX"
      done < "$PEERS_FILE"
    else
      echo "peers=0"
    fi
    ;;
  add-peer)
    NAME="${2:-}"
    PUBKEY="${3:-}"
    SPEC_IP="${4:-}"
    if [ -z "$NAME" ] || [ -z "$PUBKEY" ]; then
      echo "error=missing name or pubkey" >&2
      exit 2
    fi
    mkdir -p "$(dirname "$PEERS_FILE")"
    touch "$PEERS_FILE"

    # Eski kayıt varsa temizle
    sed -i "/^$NAME|/d" "$PEERS_FILE"
    
    # 10.13.13.X IP Dağıtımı (Çakışma korumalı & En küçük boş IP seçici)
    if [ -n "$SPEC_IP" ] && [[ "$SPEC_IP" =~ ^10\.13\.13\.([2-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-4])$ ]]; then
      NEW_IP="$SPEC_IP"
    else
      USED_OCTETS=$(grep -oE "10\.13\.13\.[0-9]+" "$PEERS_FILE" 2>/dev/null | cut -d'.' -f4 | sort -n || true)
      NEW_OCTET=2
      while [ "$NEW_OCTET" -le 254 ]; do
        if ! echo "$USED_OCTETS" | grep -qx "$NEW_OCTET"; then
          break
        fi
        NEW_OCTET=$((NEW_OCTET + 1))
      done
      if [ "$NEW_OCTET" -gt 254 ]; then
        echo "error=ip pool exhausted (max 253 peers)" >&2
        exit 3
      fi
      NEW_IP="10.13.13.${NEW_OCTET}"
    fi
    
    # WireGuard'a ekle
    wg set $WG_IF peer "$PUBKEY" allowed-ips "${NEW_IP}/32"
    echo "$NAME|$PUBKEY|$NEW_IP" >> "$PEERS_FILE"
    
    # wg0.conf kalıcı kayıt (varsa eskiyi temizleyip yenisini ekle)
    if [ -f /etc/wireguard/wg0.conf ]; then
      python3 -c "
import sys, re
pub = sys.argv[1]
with open('/etc/wireguard/wg0.conf', 'r') as f:
    text = f.read()
pattern = r'(?ms)\n*#\s*Peer:\s*.*?\n\[Peer\]\s*\n(?:(?!\[Peer\]|\[Interface\]).)*?PublicKey\s*=\s*' + re.escape(pub) + r'.*?(?=\n\[|\Z)'
text = re.sub(pattern, '', text)
with open('/etc/wireguard/wg0.conf', 'w') as f:
    f.write(text.strip() + '\n')
" "$PUBKEY" 2>/dev/null || true

      cat >> /etc/wireguard/wg0.conf << PCONF

# Peer: $NAME
[Peer]
PublicKey = $PUBKEY
AllowedIPs = ${NEW_IP}/32
PCONF
    fi
    
    SERVER_PUB=$(cat /etc/wireguard/server.pub)
    PUB_IP=$(curl -s -4 ifconfig.me || ip route get 1.1.1.1 | awk '{print $7}')
    ENDPOINT="${PUB_IP}:51820"
    echo "added=$NAME|$NEW_IP|$SERVER_PUB|$ENDPOINT"
    ;;
  remove-peer)
    NAME="${2:-}"
    PUBKEY="${3:-}"
    if [ -z "$PUBKEY" ] && [ -f "$PEERS_FILE" ]; then
      PUBKEY=$(grep -F "$NAME|" "$PEERS_FILE" | cut -d'|' -f2 | head -n1 || true)
    fi
    if [ -n "$PUBKEY" ]; then
      wg set $WG_IF peer "$PUBKEY" remove 2>/dev/null || true
    fi
    if [ -f "$PEERS_FILE" ]; then
      sed -i "/^$NAME|/d" "$PEERS_FILE"
    fi
    # wg0.conf dosyasından da kalıcı olarak sil (Rebootta geri gelmesini önle)
    if [ -f /etc/wireguard/wg0.conf ] && [ -n "$PUBKEY" ]; then
      python3 -c "
import sys, re
pub = sys.argv[1]
with open('/etc/wireguard/wg0.conf', 'r') as f:
    text = f.read()
pattern = r'(?ms)\n*#\s*Peer:\s*.*?\n\[Peer\]\s*\n(?:(?!\[Peer\]|\[Interface\]).)*?PublicKey\s*=\s*' + re.escape(pub) + r'.*?(?=\n\[|\Z)'
text = re.sub(pattern, '', text)
with open('/etc/wireguard/wg0.conf', 'w') as f:
    f.write(text.strip() + '\n')
" "$PUBKEY" 2>/dev/null || true
    fi
    echo "removed=$NAME"
    ;;
  *)
    echo "invalid action" >&2
    exit 2
    ;;
esac
CTL
chmod 755 /usr/local/bin/vpnctl

# 9. Servisi Başlat ve Etkinleştir
systemctl enable wg-quick@$WG_IF
systemctl restart wg-quick@$WG_IF

echo "=========================================================="
echo "  mFkVpN WireGuard Düğümü Başarıyla Kuruldu!             "
echo "  Sunucu Public Key : $SERVER_PUB"
echo "  Port              : $WG_PORT/UDP"
echo "  Tünel Durumu      : $(systemctl is-active wg-quick@$WG_IF)"
echo "=========================================================="
