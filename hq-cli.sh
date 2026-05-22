#!/bin/bash
# ============================================================
#  HQ-CLI — настройка (Ред ОС 8.0.2)
#  ens160     — базовый (без IP)
#  ens160.200 — VLAN200 DHCP (получает от HQ-RTR)
# ============================================================
set -e

echo "=== [1] Имя хоста ==="
hostnamectl set-hostname hq-cli.au-team.irpo

echo "=== [2] Часовой пояс ==="
timedatectl set-timezone Europe/Moscow

echo "=== [3] ens160.200 — DHCP (VLAN200) ==="
nmcli connection add type vlan con-name ens160.200 ifname ens160.200 \
    dev ens160 id 200 \
    ipv4.method auto \
    ipv6.method ignore \
    2>/dev/null || \
nmcli connection modify ens160.200 \
    ipv4.method auto ipv6.method ignore
nmcli connection up ens160.200



echo "=== HQ-CLI ГОТОВ ==="
ip -br a
echo "--- DHCP адрес ---"
ip a show ens160.200
