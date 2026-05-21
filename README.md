# ДЭ-2026 Модуль 1 — Финальная шпаргалка

## Реальные интерфейсы машин

|Машина|Интерфейс |IP            |Шлюз       |
|------|----------|--------------|-----------|
|ISP   |ens160    |DHCP          |—          |
|ISP   |ens192    |172.16.1.1/28 |—          |
|ISP   |ens224    |172.16.2.1/28 |—          |
|HQ-RTR|ens160    |172.16.1.2/28 |172.16.1.1 |
|HQ-RTR|ens160.100|192.168.1.1/27|—          |
|HQ-RTR|ens160.200|192.168.2.1/28|—          |
|HQ-RTR|ens160.999|192.168.3.1/29|—          |
|HQ-RTR|tun1 (GRE)|10.0.0.1/30   |—          |
|HQ-SRV|ens160.100|192.168.1.2/27|192.168.1.1|
|HQ-CLI|ens160.200|DHCP          |192.168.2.1|
|BR-RTR|ens160    |172.16.2.2/28 |172.16.2.1 |
|BR-RTR|ens192    |192.168.4.1/28|—          |
|BR-RTR|tun1 (GRE)|10.0.0.2/30   |—          |
|BR-SRV|ens160    |192.168.4.2/28|192.168.4.1|

-----

## Порядок на экзамене

### Шаг 1 — дать интернет каждой машине (вручную, ~30 сек)

**ISP** — уже имеет DHCP на ens160, сразу качай скрипт.

**HQ-RTR:**

```bash
nmcli connection modify ens160 ipv4.method manual ipv4.addresses 172.16.1.2/28 ipv4.gateway 172.16.1.1 ipv6.method ignore && nmcli connection up ens160
```

**BR-RTR:**

```bash
nmcli connection modify ens160 ipv4.method manual ipv4.addresses 172.16.2.2/28 ipv4.gateway 172.16.2.1 ipv6.method ignore && nmcli connection up ens160
```

**HQ-SRV** (через HQ-RTR, нужен VLAN100):

```bash
nmcli connection add type vlan con-name ens160.100 ifname ens160.100 dev ens160 id 100 ipv4.method manual ipv4.addresses 192.168.1.2/27 ipv4.gateway 192.168.1.1 ipv6.method ignore && nmcli connection up ens160.100
```

**BR-SRV:**

```bash
nmcli connection modify ens160 ipv4.method manual ipv4.addresses 192.168.4.2/28 ipv4.gateway 192.168.4.1 ipv6.method ignore && nmcli connection up ens160
```

**HQ-CLI** — получит IP через DHCP автоматически после настройки HQ-RTR.

-----

### Шаг 2 — запуск скриптов (замени НИК/РЕПО!)

```bash
# 1. ISP
curl -O https://raw.githubusercontent.com/НИК/РЕПО/main/isp.sh && bash isp.sh

# 2. HQ-RTR
curl -O https://raw.githubusercontent.com/НИК/РЕПО/main/hq-rtr.sh && bash hq-rtr.sh

# 3. BR-RTR
curl -O https://raw.githubusercontent.com/НИК/РЕПО/main/br-rtr.sh && bash br-rtr.sh

# 4. HQ-SRV
curl -O https://raw.githubusercontent.com/НИК/РЕПО/main/hq-srv.sh && bash hq-srv.sh

# 5. BR-SRV
curl -O https://raw.githubusercontent.com/НИК/РЕПО/main/br-srv.sh && bash br-srv.sh

# 6. HQ-CLI (последним)
curl -O https://raw.githubusercontent.com/НИК/РЕПО/main/hq-cli.sh && bash hq-cli.sh
```

-----

## Проверка

```bash
# Туннель (с HQ-RTR)
ping -c 3 10.0.0.2

# OSPF (с HQ-RTR или BR-RTR)
vtysh -c "show ip ospf neighbor"
vtysh -c "show ip route ospf"

# DHCP (на HQ-CLI)
ip a show ens160.200

# DNS (с любой машины)
dig @192.168.1.2 hq-srv.au-team.irpo +short
dig @192.168.1.2 moodle.au-team.irpo +short
dig -x 192.168.1.2 @192.168.1.2 +short

# SSH
ssh -p 2024 sshuser@192.168.1.2
```