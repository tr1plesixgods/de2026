#!/bin/bash
# ============================================================
#  BR-RTR — настройка (Ред ОС 8.0.2)
#  ens160 — WAN 172.16.2.2/28, gw 172.16.2.1
#  ens192 — LAN 192.168.4.1/28 (BR-Net)
#  tun1   — GRE 10.0.0.2/30, remote 172.16.1.2
#  NAT: oifname ens160
#  OSPF: tun1, сети 10.0.0.0/30 + 192.168.4.0/28
# ============================================================
set -e

echo "=== [1] Имя хоста ==="
hostnamectl set-hostname br-rtr.au-team.irpo

echo "=== [2] Часовой пояс ==="
timedatectl set-timezone Europe/Moscow

echo "=== [3] Форвардинг ==="
grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

echo "=== [4] Установка пакетов ==="
dnf install -y frr

echo "=== [5] ens160 — WAN (172.16.2.2/28) ==="
nmcli connection modify ens160 \
    ipv4.method manual \
    ipv4.addresses 172.16.2.2/28 \
    ipv4.gateway 172.16.2.1 \
    ipv6.method ignore
nmcli connection up ens160

echo "=== [6] ens192 — LAN (192.168.4.1/28) ==="
nmcli connection add type ethernet ifname ens192 con-name ens192 \
    ipv4.method manual ipv4.addresses 192.168.4.1/28 ipv6.method ignore \
    2>/dev/null || \
nmcli connection modify ens192 \
    ipv4.method manual ipv4.addresses 192.168.4.1/28 ipv6.method ignore
nmcli connection up ens192

echo "=== [7] GRE туннель tun1 → HQ-RTR ==="
nmcli connection delete tun1 2>/dev/null || true
nmcli connection add type ip-tunnel con-name tun1 ifname tun1 \
    ip-tunnel.mode gre \
    ip-tunnel.parent ens160 \
    ip-tunnel.local 172.16.2.2 \
    ip-tunnel.remote 172.16.1.2 \
    ip-tunnel.ttl 64 \
    ipv4.method manual ipv4.addresses 10.0.0.2/30 ipv6.method ignore
nmcli connection up tun1

echo "=== [8] OSPF через FRR ==="
sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr

vtysh <<EOF
configure terminal
interface tun1
 ip ospf authentication
 ip ospf authentication-key P@ssword
 no ip ospf passive
exit
router ospf
 passive-interface default
 no passive-interface tun1
 network 10.0.0.0/30 area 0
 network 192.168.4.0/28 area 0
 area 0 authentication
exit
exit
write
EOF

systemctl restart frr

echo "=== [9] NAT через nftables ==="
cat > /etc/nftables/br_nat.nft <<EOF
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "ens160" masquerade
    }
}
EOF
grep -q 'br_nat.nft' /etc/sysconfig/nftables.conf || \
    echo 'include "/etc/nftables/br_nat.nft"' >> /etc/sysconfig/nftables.conf
systemctl enable --now nftables
systemctl restart nftables

echo "=== [10] Пользователи ==="
useradd sshuser -u 1010 -U 2>/dev/null || true
echo "sshuser:P@ssw0rd" | chpasswd
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser
chmod 440 /etc/sudoers.d/sshuser

useradd net_admin -U 2>/dev/null || true
echo "net_admin:P@ssw0rd" | chpasswd
echo "net_admin ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/net_admin
chmod 440 /etc/sudoers.d/net_admin

echo "=== [11] SSH ==="
echo "Authorized access only" > /etc/ssh/banner_ssh
sed -i 's/^#\?Port .*/Port 2024/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' /etc/ssh/sshd_config
sed -i 's/^#\?Banner .*/Banner \/etc\/ssh\/banner_ssh/' /etc/ssh/sshd_config
grep -q "^AllowUsers" /etc/ssh/sshd_config || echo "AllowUsers sshuser" >> /etc/ssh/sshd_config
systemctl enable sshd && systemctl restart sshd

echo "=== BR-RTR ГОТОВ ==="
ip -br a
echo "--- Туннель ---"
ping -c 2 10.0.0.1 || echo "Проверь HQ-RTR"
