#!/bin/bash
# ============================================================
#  BR-SRV — настройка (Ред ОС 8.0.2)
#  ens160 — 192.168.4.2/28, gw 192.168.4.1
# ============================================================
set -e

echo "=== [1] Имя хоста ==="
hostnamectl set-hostname br-srv.au-team.irpo

echo "=== [2] Часовой пояс ==="
timedatectl set-timezone Europe/Moscow

echo "=== [3] ens160 — 192.168.4.2/28 ==="
nmcli connection modify ens160 \
    ipv4.method manual \
    ipv4.addresses 192.168.4.2/28 \
    ipv4.gateway 192.168.4.1 \
    ipv4.dns 192.168.1.2 \
    ipv6.method ignore
nmcli connection up ens160

echo "=== [4] Пользователь sshuser ==="
useradd sshuser -u 1010 -U 2>/dev/null || true
echo "sshuser:P@ssw0rd" | chpasswd
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser
chmod 440 /etc/sudoers.d/sshuser

echo "=== [5] SSH ==="
echo "Authorized access only" > /etc/ssh/banner_ssh
sed -i 's/^#\?Port .*/Port 2024/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' /etc/ssh/sshd_config
sed -i 's/^#\?Banner .*/Banner \/etc\/ssh\/banner_ssh/' /etc/ssh/sshd_config
grep -q "^AllowUsers" /etc/ssh/sshd_config || echo "AllowUsers sshuser" >> /etc/ssh/sshd_config
systemctl enable sshd && systemctl restart sshd

echo "=== BR-SRV ГОТОВ ==="
ip -br a
