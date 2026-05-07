#!/bin/bash
# Zivpn Full Uninstaller
# Menghapus seluruh komponen sampai bersih

echo -e "--- Memulai Proses Uninstall Full ---"

# 1. Menghentikan dan Menghapus Service
echo "Menghentikan service ZIVPN..."
systemctl stop zivpn.service 2>/dev/null
systemctl disable zivpn.service 2>/dev/null
rm /etc/systemd/system/zivpn.service 2>/dev/null
systemctl daemon-reload

# 2. Menghapus Binary dan Konfigurasi
echo "Menghapus file binary dan folder konfigurasi..."
rm /usr/local/bin/zivpn 2>/dev/null
rm /usr/local/bin/menu 2>/dev/null
rm  /usr/local/bin/autodel.sh 2>/dev/null
rm -rf /etc/zivpn 2>/dev/null
rm -rf /etc/letsencrypt/live/$(hostname) 2>/dev/null # Opsional: Menghapus SSL jika ada

# 3. Membersihkan Cronjob (Auto Reboot & Auto Expired)
echo "Membersihkan pengaturan cronjob..."
crontab -l | grep -v "/sbin/reboot" | crontab - 2>/dev/null
crontab -l | grep -v "/usr/local/bin/autodel.sh" | crontab - 2>/dev/null
crontab -l | grep -v "systemctl restart zivpn.service" | crontab - 2>/dev/null
crontab -l | grep -v "netfilter-persistent reload" | crontab - 2>/dev/null

# 4. Mengembalikan Pengaturan Kernel (BBR)
echo "Menghapus optimasi BBR dari sysctl..."
sed -i '/net.core.default_qdisc=fq/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control=bbr/d' /etc/sysctl.conf
sysctl -p 2>/dev/null

# 5. Membersihkan Firewall (Iptables & UFW)
echo "Membersihkan aturan firewall..."
# Mencari interface default
interface=$(ip -4 route ls|grep default|grep -Po '(?<=dev )(\S+)'|head -1)
iptables -t nat -D PREROUTING -i $interface -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null
ufw delete allow 6000:19999/udp 2>/dev/null
ufw delete allow 5667/udp 2>/dev/null
ufw delete allow 80/tcp 2>/dev/null

# 6. Menghapus file sisa di root
rm /root/install.sh 2>/dev/null
rm /root/uninstall.sh 2>/dev/null

echo "======================================="
echo " UNINSTALL SELESAI!"
echo " Seluruh file dan konfigurasi dihapus."
echo "======================================="
