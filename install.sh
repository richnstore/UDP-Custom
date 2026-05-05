#!/bin/bash
# prompt by zee made with AI

# 1. Update & Dependencies
apt-get update && apt-get upgrade -y
apt-get install -y wget curl openssl iptables ufw certbot cron jq

# 2. Kernel Optimization (BBR)
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# 3. Zivpn Binary & Config Setup
mkdir -p /etc/zivpn
wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn
[ ! -f /etc/zivpn/config.json ] && wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O /etc/zivpn/config.json

# Init Files
touch /etc/zivpn/expiration.list
echo "BOT_TOKEN=\"\"" > /etc/zivpn/bot.conf
echo "ADMIN_ID=\"\"" >> /etc/zivpn/bot.conf

# 4. Create Advanced Manager (The 'menu' command)
cat <<'EOF' > /usr/local/bin/menu
#!/bin/bash
CONFIG_FILE="/etc/zivpn/config.json"
EXP_FILE="/etc/zivpn/expiration.list"
BOT_CONF="/etc/zivpn/bot.conf"
source $BOT_CONF

send_telegram() {
    if [[ -n "$BOT_TOKEN" && -n "$ADMIN_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$ADMIN_ID" -d text="$1" -d parse_mode="HTML" > /dev/null
    fi
}

auto_delete() {
    today=$(date +%Y-%m-%d)
    while IFS="|" read -r user exp_date; do
        if [[ "$today" > "$exp_date" ]]; then
            sed -i "s/\"$user\"//g" "$CONFIG_FILE"
            sed -i 's/\[\s*,/\[/g; s/,\s*\]/\]/g; s/,\s*,/,/g' "$CONFIG_FILE"
            sed -i "/^$user|$exp_date/d" "$EXP_FILE"
            send_telegram "⚠️ <b>Masa Aktif Habis</b>%0AUser: <code>$user</code>%0AStatus: Telah dihapus otomatis."
            systemctl restart zivpn.service
        fi
    done < "$EXP_FILE"
}

backup_data() {
    if [[ -z "$BOT_TOKEN" ]]; then echo "Bot Token belum diatur!"; return; fi
    zip_file="/root/backup_zivpn.zip"
    zip -r $zip_file $CONFIG_FILE $EXP_FILE > /dev/null
    curl -s -F chat_id="$ADMIN_ID" -F document=@"$zip_file" \
    -F caption="✅ <b>Backup ZIVPN</b>%0ADate: $(date)" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" > /dev/null
    rm $zip_file
    echo "Backup dikirim ke Telegram."
    sleep 2
}

restore_data() {
    echo "Mencari file backup terakhir di Bot..."
    file_id=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates" | jq -r '.result | map(select(.message.document != null)) | last | .message.document.file_id')
    if [[ "$file_id" == "null" ]]; then echo "File backup tidak ditemukan!"; return; fi
    
    file_path=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getFile?file_id=$file_id" | jq -r '.result.file_path')
    wget -O /root/restore.zip "https://api.telegram.org/api/file/bot$BOT_TOKEN/$file_path"
    unzip -o /root/restore.zip -d /
    rm /root/restore.zip
    systemctl restart zivpn.service
    echo "Restore selesai!"
    sleep 2
}

while true; do
    auto_delete
    clear
    echo "====================================="
    echo "        SIMPLE ZIVPN MANAGER         "
    echo "====================================="
    echo " 1. Tambah Akun Baru"
    echo " 2. Lihat Daftar Akun"
    echo " 3. Hapus Akun"
    echo " 4. Backup ke Telegram"
    echo " 5. Restore dari Telegram"
    echo " 6. Pengaturan Bot (Token/ID)"
    echo " 7. Pasang SSL Domain"
    echo " 0. Exit"
    echo "====================================="
    read -p "Pilihan: " opt

    case $opt in
        1)
            read -p "User/Pass: " user
            read -p "Masa Aktif (Hari): " days
            exp=$(date -d "+$days days" +%Y-%m-%d)
            sed -i "s/\"config\":\s*\[/\"config\": \[\"$user\", /g" "$CONFIG_FILE"
            sed -i 's/, \]/ \]/g; s/, ,/, /g' "$CONFIG_FILE"
            echo "$user|$exp" >> "$EXP_FILE"
            send_telegram "✅ <b>Berhasill Membuat/Memperpanjang Akun</b>%0AUser: <code>$user</code>%0AExpired: <code>$exp</code> ($days Hari)"
            systemctl restart zivpn.service
            ;;
        2)
            echo -e "\nUser | Expired\n----------------"
            cat $EXP_FILE | column -t -s "|"
            read -p "Tekan Enter..."
            ;;
        3)
            read -p "User dihapus: " del_user
            sed -i "s/\"$del_user\"//g" "$CONFIG_FILE"
            sed -i 's/\[\s*,/\[/g; s/,\s*\]/\]/g; s/,\s*,/,/g' "$CONFIG_FILE"
            sed -i "/^$del_user|/d" "$EXP_FILE"
            systemctl restart zivpn.service
            ;;
        4) backup_data ;;
        5) restore_data ;;
        6)
            read -p "Masukkan BOT TOKEN: " token
            read -p "Masukkan ADMIN ID: " aid
            echo "BOT_TOKEN=\"$token\"" > $BOT_CONF
            echo "ADMIN_ID=\"$aid\"" >> $BOT_CONF
            source $BOT_CONF
            ;;
        7)
            read -p "Domain: " domain
            certbot certonly --standalone -d $domain --agree-tos --non-interactive -m admin@$domain
            cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/zivpn/zivpn.crt
            cp /etc/letsencrypt/live/$domain/privkey.pem /etc/zivpn/zivpn.key
            systemctl restart zivpn.service
            ;;
        0) exit 0 ;;
        *) echo "Pilihan salah!"; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/menu

# 5. Service & Cron
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
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
[Install]
WantedBy=multi-user.target
EOF

(crontab -l 2>/dev/null; echo "05 00 * * * /sbin/reboot") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/menu auto_delete") | crontab -

systemctl daemon-reload
systemctl enable zivpn.service
systemctl start zivpn.service

echo "Instalasi Selesai! Ketik 'menu' untuk memulai."
