#!/bin/bash
# ============================================================
#  HQ-RTR — настройка (Ред ОС 8.0.2)
#  ens160    — WAN 172.16.1.2/28, gw 172.16.1.1
#  ens160.100 — VLAN100 192.168.1.1/27 (SRV-Net)
#  ens160.200 — VLAN200 192.168.2.1/28 (CLI-Net)
#  ens160.999 — VLAN999 192.168.3.1/29 (HQ-Net)
#  tun1       — GRE 10.0.0.1/30, remote 172.16.2.2
#  NAT: oifname ens160
#  OSPF: tun1, сети 10.0.0.0/30 + все VLAN
# ============================================================
set -e

echo "=== [1] Имя хоста ==="
hostnamectl set-hostname hq-rtr.au-team.irpo

echo "=== [2] Часовой пояс ==="
timedatectl set-timezone Europe/Moscow

echo "=== [3] Форвардинг ==="
grep -q "net.ipv4.ip_forward" /etc/sysctl.conf || echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

echo "=== [4] Установка пакетов ==="
dnf install -y frr

echo "=== [5] ens160 — WAN (172.16.1.2/28) ==="
nmcli connection modify ens160 \
    ipv4.method manual \
    ipv4.addresses 172.16.1.2/28 \
    ipv4.gateway 172.16.1.1 \
    ipv6.method ignore
nmcli connection up ens160

echo "=== [6] VLAN 100 — 192.168.1.1/27 ==="
nmcli connection add type vlan con-name ens160.100 ifname ens160.100 \
    dev ens160 id 100 \
    ipv4.method manual ipv4.addresses 192.168.1.1/27 ipv6.method ignore \
    2>/dev/null || \
nmcli connection modify ens160.100 \
    ipv4.method manual ipv4.addresses 192.168.1.1/27 ipv6.method ignore
nmcli connection up ens160.100

echo "=== [7] VLAN 200 — 192.168.2.1/28 ==="
nmcli connection add type vlan con-name ens160.200 ifname ens160.200 \
    dev ens160 id 200 \
    ipv4.method manual ipv4.addresses 192.168.2.1/28 ipv6.method ignore \
    2>/dev/null || \
nmcli connection modify ens160.200 \
    ipv4.method manual ipv4.addresses 192.168.2.1/28 ipv6.method ignore
nmcli connection up ens160.200

echo "=== [8] VLAN 999 — 192.168.3.1/29 ==="
nmcli connection add type vlan con-name ens160.999 ifname ens160.999 \
    dev ens160 id 999 \
    ipv4.method manual ipv4.addresses 192.168.3.1/29 ipv6.method ignore \
    2>/dev/null || \
nmcli connection modify ens160.999 \
    ipv4.method manual ipv4.addresses 192.168.3.1/29 ipv6.method ignore
nmcli connection up ens160.999

echo "=== [9] GRE туннель tun1 → BR-RTR ==="
nmcli connection delete tun1 2>/dev/null || true
nmcli connection add type ip-tunnel con-name tun1 ifname tun1 \
    ip-tunnel.mode gre \
    ip-tunnel.parent ens160 \
    ip-tunnel.local 172.16.1.2 \
    ip-tunnel.remote 172.16.2.2 \
    ip-tunnel.ttl 64 \
    ipv4.method manual ipv4.addresses 10.0.0.1/30 ipv6.method ignore
nmcli connection up tun1

echo "=== [10] OSPF через FRR ==="
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
 network 192.168.1.0/27 area 0
 network 192.168.2.0/28 area 0
 network 192.168.3.0/29 area 0
 area 0 authentication
exit
exit
write
EOF

systemctl restart frr

echo "=== [11] DHCP для VLAN200 (HQ-CLI) ==="
dnf install -y dhcp-server
cat > /etc/dhcp/dhcpd.conf <<EOF
subnet 192.168.2.0 netmask 255.255.255.240 {
    range 192.168.2.2 192.168.2.14;
    option routers 192.168.2.1;
    option domain-name-servers 192.168.1.2;
    option domain-name "au-team.irpo";
    default-lease-time 600;
    max-lease-time 7200;
}
EOF
sed -i 's/^DHCPDARGS=.*/DHCPDARGS="ens160.200"/' /etc/sysconfig/dhcpd 2>/dev/null || \
    echo 'DHCPDARGS="ens160.200"' >> /etc/sysconfig/dhcpd
systemctl enable --now dhcpd

echo "=== [12] NAT через nftables ==="
cat > /etc/nftables/hq_nat.nft <<EOF
table inet nat {
    chain POSTROUTING {
        type nat hook postrouting priority srcnat; policy accept;
        oifname "ens160" masquerade
    }
}
EOF
grep -q 'hq_nat.nft' /etc/sysconfig/nftables.conf || \
    echo 'include "/etc/nftables/hq_nat.nft"' >> /etc/sysconfig/nftables.conf
systemctl enable --now nftables
systemctl restart nftables

echo "=== [13] Пользователи ==="

useradd net_admin -U 2>/dev/null || true
echo "net_admin:P@ssw0rd" | chpasswd
echo "net_admin ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/net_admin
chmod 440 /etc/sudoers.d/net_admin


echo "=== HQ-RTR ГОТОВ ==="
ip -br a
echo "--- Туннель ---"
ping -c 2 10.0.0.2 || echo "BR-RTR ещё не настроен"
