#!/bin/bash
# ==========================================
# ZIVPN AUTO DELETE SCRIPT
# ==========================================

CONFIG_FILE="/etc/zivpn/config.json"
EXP_FILE="/etc/zivpn/expiration.list"
BOT_CONF="/etc/zivpn/bot.conf"

# Load Konfigurasi Bot
[ -f $BOT_CONF ] && source $BOT_CONF

send_telegram() {
    if [[ -n "$BOT_TOKEN" && -n "$ADMIN_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$ADMIN_ID" -d text="$1" -d parse_mode="HTML" > /dev/null
    fi
}

# Ambil tanggal hari ini
today=$(date +%Y-%m-%d)

# Proses pengecekan
while IFS="|" read -r user exp_date; do
    # Jika hari ini >= tanggal expired, maka hapus
    if [[ "$today" == "$exp_date" || "$today" > "$exp_date" ]]; then
        # Hapus user dari config.json
        sed -i "s/\"$user\"//g" "$CONFIG_FILE"
        # Rapikan format JSON
        sed -i 's/\[\s*,/\[/g; s/,\s*\]/\]/g; s/,\s*,/,/g' "$CONFIG_FILE"
        
        # Hapus user dari expiration.list
        sed -i "/^$user|$exp_date/d" "$EXP_FILE"
        
        # Notifikasi & Restart
        send_telegram "⚠️ <b>Masa Aktif Habis</b>%0AUser: <code>$user</code>%0AStatus: Telah dihapus otomatis."
        systemctl restart zivpn.service
    fi
done < "$EXP_FILE"
