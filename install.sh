#!/bin/bash
# Zivpn All-in-One Installer

# 1. Update & Dependencies
echo -e "--- Installing Dependencies ---"
apt-get update && apt-get upgrade -y
apt-get install -y wget curl openssl iptables ufw certbot cron jq zip unzip vnstat bc

# Konfigurasi vnStat
systemctl enable vnstat
systemctl start vnstat

# 2. Kernel Optimization (BBR)
echo -e "--- Optimizing Connection (BBR) ---"
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

# 3. Zivpn Binary & Config Setup
echo -e "--- Downloading Zivpn Service ---"
systemctl stop zivpn.service 2>/dev/null
mkdir -p /etc/zivpn
wget https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64 -O /usr/local/bin/zivpn
chmod +x /usr/local/bin/zivpn
[ ! -f /etc/zivpn/config.json ] && wget https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json -O /etc/zivpn/config.json

# Init Files
touch /etc/zivpn/expiration.list
[ ! -f /etc/zivpn/bot.conf ] && echo -e "BOT_TOKEN=\"\"\nADMIN_ID=\"\"" > /etc/zivpn/bot.conf

# 4. Create Advanced Manager (The 'menu' command)
cat <<'EOF' > /usr/local/bin/menu
#!/bin/bash
CONFIG_FILE="/etc/zivpn/config.json"
EXP_FILE="/etc/zivpn/expiration.list"
BOT_CONF="/etc/zivpn/bot.conf"
source $BOT_CONF

pause() {
    read -p $'\nTekan [Enter] untuk kembali ke menu...'
}

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
    if [[ -z "$BOT_TOKEN" ]]; then echo "Bot Token belum diatur!"; pause; return; fi
    zip_file="/root/backup_zivpn.zip"
    zip -j $zip_file $CONFIG_FILE $EXP_FILE > /dev/null
    curl -s -F chat_id="$ADMIN_ID" -F document=@"$zip_file" \
    -F caption="✅ <b>Backup ZIVPN</b>%0ADate: $(date)" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" > /dev/null
    rm $zip_file
    echo "Backup berhasil dikirim ke Telegram."
    pause
}

restore_data() {
    if [[ -z "$BOT_TOKEN" ]]; then echo "Bot Token belum diatur!"; pause; return; fi
    echo "Mencari file backup terakhir di Bot..."
    updates=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getUpdates")
    file_id=$(echo $updates | jq -r '.result | map(select(.message.document != null)) | last | .message.document.file_id')
    
    if [[ "$file_id" == "null" ]]; then 
        echo "File backup tidak ditemukan di chat bot!"
        pause
        return
    fi
    
    file_path=$(curl -s "https://api.telegram.org/bot$BOT_TOKEN/getFile?file_id=$file_id" | jq -r '.result.file_path')
    wget -q -O /root/restore.zip "https://api.telegram.org/file/bot$BOT_TOKEN/$file_path"
    unzip -o /root/restore.zip -d /etc/zivpn/ > /dev/null
    rm /root/restore.zip
    systemctl restart zivpn.service
    echo "✅Restore selesai! Data telah diperbarui."
    pause
}

while true; do
    auto_delete
    clear
    
    # Ambil Data Sistem
    IPVPS=$(curl -s ifconfig.me)
    DOMAIN=$(openssl x509 -noout -subject -in /etc/zivpn/zivpn.crt 2>/dev/null | sed -n 's/^subject=.*CN = \(.*\)$/\1/p')
    ISP=$(curl -s ipinfo.io/org | cut -d " " -f 2-)
    CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
    RAM=$(free -m | awk '/Mem:/ { printf("%3.1f%%", $3/$2*100) }')
    
    # Ambil Data Bandwidth
    INTF=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
    DAILY=$(vnstat -i $INTF --oneline | cut -d ';' -f 4)
    MONTHLY=$(vnstat -i $INTF --oneline | cut -d ';' -f 10)

    echo "=================================================="
    echo "               SYSTEM INFORMATION                 "
    echo "=================================================="
    echo " IP VPS      : $IPVPS"
    echo " Domain      : $DOMAIN"
    echo " ISP         : $ISP"
    echo " CPU Usage   : $CPU"
    echo " RAM Usage   : $RAM"
    echo " Bandwidth   : Hari ($DAILY) | Bulan ($MONTHLY)"
    echo "=================================================="
    echo "         ZIVPN MANAGER BY RICH NARENDRA           "
    echo "=================================================="
    echo " 1. Tambah Akun"
    echo " 2. Lihat Daftar Akun"
    echo " 3. Hapus Akun"
    echo " 4. Backup ke Telegram"
    echo " 5. Restore dari Telegram"
    echo " 6. Ganti Token dan ID BOT"
    echo " 7. Pasang SSL Domain"
    echo " 0. Exit"
    echo "=================================================="
    read -p "Pilihan: " opt

    case $opt in
        1)
            read -p "User/Pass: " user
            read -p "Masa Aktif (Hari): " days
            exp=$(date -d "+$days days" +%Y-%m-%d)
            sed -i "s/\"config\":\s*\[/\"config\": \[\"$user\", /g" "$CONFIG_FILE"
            sed -i 's/, \]/ \]/g; s/, ,/, /g' "$CONFIG_FILE"
            echo "$user|$exp" >> "$EXP_FILE"
            send_telegram "✅ <b>Berhasil Dibuat</b>%0APelanggan: <code>$user</code>%0AMasa Aktif: <code>$exp</code> ($days Hari)"
            systemctl restart zivpn.service
            echo "Sukses membuat user $user."
            pause
            ;;
        2)
            echo -e "\nUser | Expired\n----------------"
            cat $EXP_FILE | column -t -s "|"
            pause
            ;;
        3)
            read -p "Masukkan password user yang akan dihapus: " del_user
            # Cek apakah user ada di file expiration.list
            if grep -q "^$del_user|" "$EXP_FILE"; then
                # Proses Hapus dari config.json
                sed -i "s/\"$del_user\"//g" "$CONFIG_FILE"
                # Rapikan JSON (hapus koma ganda atau spasi berlebih)
                sed -i 's/\[\s*,/\[/g; s/,\s*\]/\]/g; s/,\s*,/,/g' "$CONFIG_FILE"
                
                # Hapus dari daftar expiration
                sed -i "/^$del_user|/d" "$EXP_FILE"
                
                systemctl restart zivpn.service
                echo -e "\n✅ Sukses: User '$del_user' telah dihapus."
                send_telegram "🗑️ <b>User Dihapus Manual</b>%0AUser: <code>$del_user</code>%0AStatus: Berhasil dihapus oleh Admin."
            else
                echo -e "\n❌ Error: User '$del_user' tidak ditemukan dalam daftar!"
            fi
            pause
            ;;
        4) backup_data ;;
        5) restore_data ;;
        6)
            read -p "Masukkan BOT TOKEN: " token
            read -p "Masukkan ADMIN ID: " aid
            echo -e "BOT_TOKEN=\"$token\"\nADMIN_ID=\"$aid\"" > $BOT_CONF
            source $BOT_CONF
            echo "Pengaturan Bot disimpan."
            pause
            ;;
        7)
            read -p "Domain: " domain
            systemctl stop zivpn.service
            certbot certonly --standalone -d $domain --agree-tos --non-interactive -m admin@$domain
            if [ -f /etc/letsencrypt/live/$domain/fullchain.pem ]; then
                cp /etc/letsencrypt/live/$domain/fullchain.pem /etc/zivpn/zivpn.crt
                cp /etc/letsencrypt/live/$domain/privkey.pem /etc/zivpn/zivpn.key
                echo "SSL Berhasil dipasang!"
            fi
            systemctl start zivpn.service
            pause
            ;;
        0) exit 0 ;;
        *) echo "Pilihan salah!"; sleep 1 ;;
    esac
done
EOF

chmod +x /usr/local/bin/menu

# 5. Firewall & Network Setup
echo -e "--- Configuring Firewall & Network ---"
iptables -t nat -A PREROUTING -i $(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1) -p udp --dport 6000:19999 -j DNAT --to-destination :5667
ufw allow 6000:19999/udp
ufw allow 5667/udp
ufw allow 80/tcp

# 6. Service & Cronjob Setup
echo -e "--- Setting Up Service & Cronjobs ---"
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

# Setup Crontab
(crontab -l 2>/dev/null; echo "05 00 * * * /sbin/reboot") | crontab -
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/menu auto_delete") | crontab -

# 7. Finalize
systemctl daemon-reload
systemctl enable zivpn.service
systemctl start zivpn.service

echo -e "======================================="
echo " INSTALASI SELESAI!"
echo " Ketik 'menu' untuk mengelola akun."
echo " Auto-Reboot: 00.05 WIB"
echo " BBR Optimization: Active"
echo "======================================="
