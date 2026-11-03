#!/usr/bin/env bash
# ==============================================================================
# mFkVpN - Hetzner / Debian / Ubuntu WireGuard Sunucu Kurulum Betiği
#
# Kullanım (repo klonu içinden, root olarak):
#   sudo ./setup_server.sh
#   sudo DEPLOY_PUBKEY="ssh-ed25519 AAAA... github-actions" ./setup_server.sh
#
# DEPLOY_PUBKEY verilirse GitHub Actions anahtarı sadece vpnctl çalıştırabilecek
# şekilde (command= kısıtlı) root'un authorized_keys dosyasına eklenir.
# Betik tekrar çalıştırılabilir: mevcut sunucu anahtarı ve peer'lar korunur.
# ==============================================================================

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "[-] Bu betik root yetkisiyle çalıştırılmalıdır (sudo ./setup_server.sh)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/server/vpnctl" ]; then
  echo "[-] $SCRIPT_DIR/server/vpnctl bulunamadı. Betiği repo klonunun içinden çalıştırın." >&2
  exit 1
fi

echo "=========================================================="
echo "  mFkVpN - Güvenli WireGuard Düğüm Kurulumu Başlatılıyor  "
echo "=========================================================="

WG_IF="wg0"
WG_PORT=51820
WG_NET="10.13.13.1/24"
PEERS_FILE="/etc/wireguard/peers.map"

# 1. Sistem Güncellemeleri ve Paketler
echo "[+] Sistem paketleri güncelleniyor..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wireguard wireguard-tools ufw fail2ban unattended-upgrades iptables iproute2 qrencode

# Otomatik güvenlik güncellemelerini etkinleştir
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# 2. Çekirdek Ağ Parametreleri
echo "[+] Çekirdek ağ parametreleri uygulanıyor (Forwarding ON, IPv6 kapalı)..."
cat > /etc/sysctl.d/99-mfkvpn.conf << 'EOF'
net.ipv4.ip_forward=1
net.ipv4.conf.all.forwarding=1
# IPv6 sızıntılarını önlemek için kapat
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
sysctl --system > /dev/null

# 3. Sıfır Günlük: journald sadece RAM'de
echo "[+] RAM-Only journald yapılandırması..."
mkdir -p /etc/systemd/journald.conf.d/
cat > /etc/systemd/journald.conf.d/zero-logs.conf << 'EOF'
[Journal]
Storage=volatile
SystemMaxUse=16M
RuntimeMaxUse=16M
EOF
systemctl restart systemd-journald

# 4. Aktif İnternet Ağ Arayüzü
PUB_NIC=$(ip route show default | awk '{print $5}' | head -n1)
PUB_NIC="${PUB_NIC:-eth0}"
echo "[+] Aktif çıkış arayüzü: $PUB_NIC"

# 5. WireGuard Sunucu Anahtarları (varsa korunur)
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
if [ ! -f /etc/wireguard/server.key ]; then
  echo "[+] Sunucu WireGuard anahtarları oluşturuluyor..."
  (umask 077 && wg genkey > /etc/wireguard/server.key)
  wg pubkey < /etc/wireguard/server.key > /etc/wireguard/server.pub
fi
SERVER_PUB=$(cat /etc/wireguard/server.pub)

# 6. wg0.conf: sadece yoksa oluştur (tekrar çalıştırmada peer'lar silinmesin)
if [ ! -f /etc/wireguard/$WG_IF.conf ]; then
  SERVER_PRIV=$(cat /etc/wireguard/server.key)
  cat > /etc/wireguard/$WG_IF.conf << EOF
[Interface]
Address = $WG_NET
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
MTU = 1360
PostUp = iptables -A FORWARD -i $WG_IF -j ACCEPT; iptables -t nat -A POSTROUTING -o $PUB_NIC -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_IF -j ACCEPT; iptables -t nat -D POSTROUTING -o $PUB_NIC -j MASQUERADE
EOF
  unset SERVER_PRIV
else
  echo "[=] Mevcut /etc/wireguard/$WG_IF.conf korunuyor."
fi
chmod 600 /etc/wireguard/$WG_IF.conf
touch "$PEERS_FILE"
chmod 600 "$PEERS_FILE"

# 7. vpnctl yönetim betiği (tek kaynak: server/vpnctl)
echo "[+] /usr/local/bin/vpnctl kuruluyor..."
install -m 755 "$SCRIPT_DIR/server/vpnctl" /usr/local/bin/vpnctl

# 8. SSH sertleştirme
SSH_PORT=$(sshd -T 2>/dev/null | awk '$1=="port" {print $2; exit}')
SSH_PORT="${SSH_PORT:-22}"

if [ -n "${DEPLOY_PUBKEY:-}" ]; then
  if ! [[ "$DEPLOY_PUBKEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)\ [A-Za-z0-9+/=]+(\ .*)?$ ]]; then
    echo "[-] DEPLOY_PUBKEY geçerli bir SSH public key değil." >&2
    exit 1
  fi
  echo "[+] GitHub Actions anahtarı vpnctl ile kısıtlanarak ekleniyor..."
  install -d -m 700 /root/.ssh
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  KEY_BODY=$(awk '{print $2}' <<< "$DEPLOY_PUBKEY")
  # Aynı anahtarın kısıtsız eski satırını kaldır
  grep -vF "$KEY_BODY" /root/.ssh/authorized_keys > /root/.ssh/authorized_keys.tmp || true
  echo "command=\"/usr/local/bin/vpnctl --ssh\",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding $DEPLOY_PUBKEY" >> /root/.ssh/authorized_keys.tmp
  mv /root/.ssh/authorized_keys.tmp /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

# Parola ile girişi sadece en az bir anahtar tanımlıysa kapat (kilitlenmeyi önle)
if [ -s /root/.ssh/authorized_keys ] || ls /home/*/.ssh/authorized_keys >/dev/null 2>&1; then
  echo "[+] SSH parola girişi kapatılıyor (sadece anahtar)..."
  mkdir -p /etc/ssh/sshd_config.d
  cat > /etc/ssh/sshd_config.d/10-mfkvpn.conf << 'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  else
    echo "[-] sshd yapılandırma testi başarısız, değişiklik geri alınıyor." >&2
    rm -f /etc/ssh/sshd_config.d/10-mfkvpn.conf
  fi
else
  echo "[!] authorized_keys bulunamadı; parola girişi AÇIK bırakıldı. Önce bir SSH anahtarı ekleyin."
fi

cat > /etc/fail2ban/jail.d/mfkvpn.local << EOF
[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
maxretry = 5
bantime = 1h
EOF
systemctl enable --now fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban || true

# 9. Güvenlik Duvarı (UFW)
echo "[+] UFW kural seti ayarlanıyor..."
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment 'SSH'
ufw allow ${WG_PORT}/udp comment 'WireGuard VPN'
sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw --force enable

# 10. Servisi Başlat ve Etkinleştir
systemctl enable wg-quick@$WG_IF
systemctl restart wg-quick@$WG_IF

echo "=========================================================="
echo "  mFkVpN WireGuard Düğümü Başarıyla Kuruldu!             "
echo "  Sunucu Public Key : $SERVER_PUB"
echo "  Port              : $WG_PORT/UDP"
echo "  Tünel Durumu      : $(systemctl is-active wg-quick@$WG_IF)"
echo ""
echo "  GitHub'a eklenecek SSH_HOST_KEY secret değeri:"
for f in /etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ecdsa_key.pub; do
  [ -f "$f" ] || continue
  if [ "$SSH_PORT" = "22" ]; then HOSTPART="<SUNUCU_IP>"; else HOSTPART="[<SUNUCU_IP>]:$SSH_PORT"; fi
  echo "  $HOSTPART $(awk '{print $1" "$2}' "$f")"
done
echo "=========================================================="
