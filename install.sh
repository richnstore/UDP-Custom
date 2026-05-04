#!/bin/bash
# Zivpn UDP Installer + Advanced Manager
# Integrated with BBR, Auto-Reboot, and SSL Support

# 1. Update & Base Dependencies
echo -e "--- Updating Server & Installing Dependencies ---"
apt-get update && apt-get upgrade -y
apt-get install -y wget curl openssl iptables ufw certbot cron

# 2. Kernel Optimization (BBR)
echo -e "--- Optimizing Connection (BBR) ---"
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# 3. Install Zivpn Binary & Config
echo -e "--- Downloading Zivpn Service ---"
systemctl stop zivpn.service 2>/dev/null
wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn
mkdir -p /etc/zivpn
wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O /etc/zivpn/config.json

# Generate Initial Certs (Self-Signed)
openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=US/ST=CA/L=LA/O=Zivpn/CN=zivpn" -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt"

# 4. Create Systemd Service
cat <<EOF > /etc/systemd/system/zivpn.service
[Unit]
Description=zivpn VPN Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# 5. Firewall & Network Setup
echo -e "--- Configuring Firewall ---"
iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 6000:19999 -j DNAT --to-destination :5667
ufw allow 6000:19999/udp
ufw allow 5667/udp
ufw allow 80/tcp

# 6. Create Account Manager (The 'menu' command)
echo -e "--- Creating Account Manager ---"
cat <<'EOF' > /usr/local/bin/menu
#!/bin/bash
CONFIG_FILE="/etc/zivpn/config.json"
EXP_FILE="/etc/zivpn/expiration.list"
touch $EXP_FILE

auto_delete() {
    today=$(date +%Y-%m-%d)
    while IFS="|" read -r user exp_date; do
        if [[ "$today" > "$exp_date" ]]; then
            sed -i "s/\"$user\"//g" "$CONFIG_FILE"
            sed -i 's/\[\s*,/\[/g; s/,\s*\]/\]/g; s/,\s*,/,/g' "$CONFIG_FILE"
            sed -i "/^$user|$exp_date/d" "$EXP_FILE"
            systemctl restart zivpn.service
        fi
    done < "$EXP_FILE"
}

# Run cleanup on start
auto_delete

clear
echo "====================================="
echo "   ZIVPN ALL-IN-ONE MANAGER          "
echo "====================================="
echo " 1. Lihat Daftar Akun"
echo " 2. Tambah Akun Baru"
echo " 3. Hapus Akun"
echo " 4. Pasang SSL Domain"
echo " 5. Keluar"
echo "====================================="
read -p "Pilih opsi [1-5]: " choice

case $choice in
    1)
        echo -e "\n--- User | Expired Date ---"
        cat $EXP_FILE | column -t -s "|"
        echo -e "---------------------------\n"
        ;;
    2)
        read -p "Password: " new_user
        read -p "Hari: " duration
        exp_date=$(date -d "+$duration days" +%Y-%m-%d)
        sed -i "s/\"config\":\s*\[/\"config\": \[\"$new_user\", /g" "$CONFIG_FILE"
        sed -i 's/, \]/ \]/g; s/, ,/, /g' "$CONFIG_FILE"
        echo "$new_user|$exp_date" >> "$EXP_FILE"
        systemctl restart zivpn.service
        echo "Akun '$new_user' aktif sampai $exp_date."
        ;;
    3)
        read -p "Password yang dihapus: " del_user
        sed -i "s/\"$del_user\"//g" "$CONFIG_FILE"
        sed -i 's/\[\s*,/\[/g; s/,\s*\]/\]/g; s/,\s*,/,/g' "$CONFIG_FILE"
        sed -i "/^$del_user|/d" "$EXP_FILE"
        systemctl restart zivpn.service
        echo "Akun '$del_user' dihapus."
        ;;
    4)
        read -p "Domain: " domain
        systemctl stop zivpn.service
        certbot certonly --standalone --preferred-challenges http -d "$domain" --agree-tos --non-interactive -m admin@$domain
        if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
            cp "/etc/letsencrypt/live/$domain/fullchain.pem" "/etc/zivpn/zivpn.crt"
            cp "/etc/letsencrypt/live/$domain/privkey.pem" "/etc/zivpn/zivpn.key"
            echo "SSL Berhasil dipasang!"
        fi
        systemctl start zivpn.service
        ;;
    5) exit 0 ;;
esac
EOF

chmod +x /usr/local/bin/menu

# 7. Setting Up Cronjobs (Auto Reboot & Auto Expired)
echo -e "--- Setting Up Cronjobs ---"
(crontab -l 2>/dev/null; echo "05 00 * * * /sbin/reboot") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/menu auto_delete") | crontab -

# Finalize
systemctl enable zivpn.service
systemctl start zivpn.service
echo -e "======================================="
echo " INSTALASI SELESAI!"
echo " Ketik 'menu' untuk mengelola akun."
echo " Auto-Reboot: 00.05"
echo " BBR: Active"
echo "======================================="
