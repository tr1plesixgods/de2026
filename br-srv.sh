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



echo "=== BR-SRV ГОТОВ ==="
ip -br a
