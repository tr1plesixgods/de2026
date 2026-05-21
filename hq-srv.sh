#!/bin/bash
# ============================================================
#  HQ-SRV — настройка (Ред ОС 8.0.2)
#  ens160     — основной интерфейс
#  ens160.100 — VLAN100 192.168.1.2/27, gw 192.168.1.1
#  DNS: bind, зоны au-team.irpo, 1.168.192, 2.168.192
# ============================================================
set -e
# Защита от дублей при повторном запуске
ALREADY_CONFIGURED=false
grep -q 'au-team.irpo' /etc/named.conf 2>/dev/null && ALREADY_CONFIGURED=true

echo "=== [1] Имя хоста ==="
hostnamectl set-hostname hq-srv.au-team.irpo

echo "=== [2] Часовой пояс ==="
timedatectl set-timezone Europe/Moscow

echo "=== [3] ens160.100 — 192.168.1.2/27 ==="
nmcli connection add type vlan con-name ens160.100 ifname ens160.100 \
    dev ens160 id 100 \
    ipv4.method manual \
    ipv4.addresses 192.168.1.2/27 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns 192.168.1.2 \
    ipv6.method ignore \
    2>/dev/null || \
nmcli connection modify ens160.100 \
    ipv4.method manual \
    ipv4.addresses 192.168.1.2/27 \
    ipv4.gateway 192.168.1.1 \
    ipv4.dns 192.168.1.2 \
    ipv6.method ignore
nmcli connection up ens160.100

echo "=== [4] Установка BIND ==="
dnf install -y bind bind-utils

echo "=== [5] Настройка named.conf ==="
sed -i 's/listen-on port 53 { 127.0.0.1; };/listen-on port 53 { any; };/' /etc/named.conf
sed -i 's/listen-on-v6 port 53 { ::1; };/listen-on-v6 port 53 { none; };/' /etc/named.conf
sed -i 's/allow-query.*{ localhost; };/allow-query     { any; };/' /etc/named.conf
sed -i 's/dnssec-validation yes;/dnssec-validation no;/' /etc/named.conf

# Добавляем форвардеры и зоны если их нет
grep -q 'forwarders' /etc/named.conf || \
    sed -i '/recursion yes;/a\\tforwarders { 8.8.8.8; 1.1.1.1; };' /etc/named.conf

# Зоны — добавляем только если их ещё нет
if [ "$ALREADY_CONFIGURED" = false ]; then
cat >> /etc/named.conf <<'EOF'

zone "au-team.irpo" {
        type master;
        file "master/au-team.db";
};

zone "1.168.192.in-addr.arpa" {
        type master;
        file "master/1.db";
};

zone "2.168.192.in-addr.arpa" {
        type master;
        file "master/2.db";
};
EOF
fi # конец блока добавления зон

echo "=== [6] Создание папки зон ==="
mkdir -p /var/named/master

echo "=== [7] Прямая зона au-team.irpo ==="
cat > /var/named/master/au-team.db <<'EOF'
$TTL 1D
@       IN SOA  au-team.irpo. adm.au-team.irpo. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        IN      NS      au-team.irpo.
        IN      A       192.168.1.2
hq-rtr  IN      A       192.168.1.1
br-rtr  IN      A       192.168.4.1
hq-cli  IN      A       192.168.2.2
br-srv  IN      A       192.168.4.2
docker  IN      A       172.16.1.1
web     IN      A       172.16.2.1
moodle  IN      CNAME   hq-srv.au-team.irpo.
wiki    IN      CNAME   hq-srv.au-team.irpo.
EOF

echo "=== [8] Обратная зона 192.168.1 ==="
cat > /var/named/master/1.db <<'EOF'
$TTL 1D
@       IN SOA  au-team.irpo. adm.au-team.irpo. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        IN      NS      au-team.irpo.
1       IN      PTR     hq-rtr.au-team.irpo.
2       IN      PTR     hq-srv.au-team.irpo.
EOF

echo "=== [9] Обратная зона 192.168.2 ==="
cat > /var/named/master/2.db <<'EOF'
$TTL 1D
@       IN SOA  au-team.irpo. adm.au-team.irpo. (
                                        0       ; serial
                                        1D      ; refresh
                                        1H      ; retry
                                        1W      ; expire
                                        3H )    ; minimum
        IN      NS      au-team.irpo.
2       IN      PTR     hq-cli.au-team.irpo.
EOF

echo "=== [10] Права ==="
chown -R root:named /var/named/master
chmod 0640 /var/named/master/*

echo "=== [11] Запуск BIND ==="
named-checkconf && echo "named.conf OK"
named-checkzone au-team.irpo /var/named/master/au-team.db
systemctl enable --now named

echo "=== [12] Пользователь sshuser ==="
useradd sshuser -u 1010 -U 2>/dev/null || true
echo "sshuser:P@ssw0rd" | chpasswd
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser
chmod 440 /etc/sudoers.d/sshuser

echo "=== [13] SSH ==="
echo "Authorized access only" > /etc/ssh/banner_ssh
sed -i 's/^#\?Port .*/Port 2024/' /etc/ssh/sshd_config
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' /etc/ssh/sshd_config
sed -i 's/^#\?Banner .*/Banner \/etc\/ssh\/banner_ssh/' /etc/ssh/sshd_config
grep -q "^AllowUsers" /etc/ssh/sshd_config || echo "AllowUsers sshuser" >> /etc/ssh/sshd_config
systemctl enable sshd && systemctl restart sshd

echo "=== HQ-SRV ГОТОВ ==="
ip -br a
echo "--- Проверка DNS ---"
dig @192.168.1.2 hq-srv.au-team.irpo +short
dig @192.168.1.2 moodle.au-team.irpo +short
