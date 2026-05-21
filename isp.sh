#!/bin/bash
# ============================================================
#  ISP — настройка (Ред ОС 8.0.2)
#  ens160 — интернет (DHCP)
#  ens192 — сторона HQ (172.16.1.1/28)
#  ens224 — сторона BR (172.16.2.1/28)
#  NAT: oifname ens160
# ============================================================
set -e

echo "=== [1] Имя хоста ==="
hostnamectl set-hostname isp.au-team.irpo

echo "=== [2] Часовой пояс ==="
timedatectl set-timezone Europe/Moscow

echo "=== [3] Форвардинг ==="
grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

echo "=== [4] ens160 — DHCP (интернет) ==="
nmcli connection modify ens160 ipv4.method auto ipv6.method ignore
nmcli connection up ens160

echo "=== [5] ens192 — 172.16.1.1/28 (ISP-HQ) ==="
nmcli connection add type ethernet ifname ens192 con-name ens192 \
    ipv4.method manual ipv4.addresses 172.16.1.1/28 ipv6.method ignore \
    2>/dev/null || \
nmcli connection modify ens192 \
    ipv4.method manual ipv4.addresses 172.16.1.1/28 ipv6.method ignore
nmcli connection up ens192

echo "=== [6] ens224 — 172.16.2.1/28 (ISP-BR) ==="
nmcli connection add type ethernet ifname ens224 con-name ens224 \
    ipv4.method manual ipv4.addresses 172.16.2.1/28 ipv6.method ignore \
    2>/dev/null || \
nmcli connection modify ens224 \
    ipv4.method manual ipv4.addresses 172.16.2.1/28 ipv6.method ignore
nmcli connection up ens224

echo "=== [7] NAT через nftables ==="
cat > /etc/nftables/isp_nat.nft <<EOF
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "ens160" masquerade
    }
}
EOF
grep -q 'isp_nat.nft' /etc/sysconfig/nftables.conf || \
    echo 'include "/etc/nftables/isp_nat.nft"' >> /etc/sysconfig/nftables.conf
systemctl enable --now nftables
systemctl restart nftables


echo "=== ISP ГОТОВ ==="
ip -br a
