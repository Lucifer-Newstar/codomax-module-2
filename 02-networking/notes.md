# Task 2 — Networking: IP addressing, DNS, ports, firewalls, security groups

Notes from the networking part of the internship. Commands are for **AlmaLinux 9** (NetworkManager + firewalld); Ubuntu differences are marked.

Contents
1. IPv4 basics
2. CIDR & subnetting (worked example)
3. Private ranges
4. DNS
5. Ports
6. Firewalls with firewalld
7. Cloud security groups vs NACLs

---

## 1. IPv4 basics

- An IPv4 address is 32 bits, written as 4 octets: `192.168.1.10`.
- The **subnet mask** splits it into a network part and a host part: `255.255.255.0` = `/24` = first 24 bits are network.
- **Network address** (all host bits 0) and **broadcast address** (all host bits 1) can't be given to hosts.
- **Gateway** = the router IP the host sends non-local traffic to.

Check my own config:
```bash
ip a                      # addresses on each interface (ifconfig is old/deprecated)
ip r                      # routing table, "default via ..." is the gateway
nmcli device status       # NetworkManager view (AlmaLinux)
hostname -I               # just the IPs
```

Static IP on AlmaLinux (NetworkManager):
```bash
sudo nmcli con mod enp0s3 ipv4.method manual \
  ipv4.addresses 192.168.56.10/24 ipv4.gateway 192.168.56.1 ipv4.dns "1.1.1.1 8.8.8.8"
sudo nmcli con up enp0s3
```
- **Ubuntu:** uses netplan (`/etc/netplan/*.yaml`, then `sudo netplan apply`).

---

## 2. CIDR & subnetting

Usable hosts = `2^(32 - prefix) - 2`.

| CIDR | Mask | Addresses | Usable hosts |
|---|---|---|---|
| /24 | 255.255.255.0 | 256 | 254 |
| /25 | 255.255.255.128 | 128 | 126 |
| /26 | 255.255.255.192 | 64 | 62 |
| /27 | 255.255.255.224 | 32 | 30 |
| /28 | 255.255.255.240 | 16 | 14 |
| /32 | 255.255.255.255 | 1 | single host (used in firewall rules) |

### Worked example: `192.168.1.0/24`
- Network: `192.168.1.0`
- Broadcast: `192.168.1.255`
- Usable: `192.168.1.1` – `192.168.1.254` (254 hosts)

### Split it into four `/26` subnets
Borrow 2 host bits → 2² = 4 subnets, each 2⁶ = 64 addresses (block size 64), 62 usable.

| Subnet | Network | Usable range | Broadcast |
|---|---|---|---|
| 1 | 192.168.1.0/26 | .1 – .62 | 192.168.1.63 |
| 2 | 192.168.1.64/26 | .65 – .126 | 192.168.1.127 |
| 3 | 192.168.1.128/26 | .129 – .190 | 192.168.1.191 |
| 4 | 192.168.1.192/26 | .193 – .254 | 192.168.1.255 |

Quick check: which subnet is `192.168.1.100` in? 100 is between 64 and 127 → subnet 2 (`192.168.1.64/26`).

Same idea in a cloud VPC: VPC `10.0.0.0/16`, public subnet `10.0.1.0/24`, private subnet `10.0.2.0/24`.
(AWS reserves 5 addresses per subnet, so a /24 gives 251 usable there.)

---

## 3. Private ranges (RFC 1918) and other special ones

| Range | CIDR | Use |
|---|---|---|
| 10.0.0.0 – 10.255.255.255 | 10.0.0.0/8 | big private networks, cloud VPCs |
| 172.16.0.0 – 172.31.255.255 | 172.16.0.0/12 | private (Docker's default bridge uses 172.17.0.0/16) |
| 192.168.0.0 – 192.168.255.255 | 192.168.0.0/16 | home / lab networks |
| 127.0.0.0/8 | loopback | `localhost` |
| 169.254.0.0/16 | link-local | no DHCP answer; also the cloud metadata IP 169.254.169.254 |
| 100.64.0.0/10 | carrier-grade NAT | ISPs |

Private IPs aren't routed on the internet — they reach out through **NAT**.

---

## 4. DNS

DNS turns names into IPs. Resolution order on Linux is set in `/etc/nsswitch.conf` (`hosts: files dns ...`), so **`/etc/hosts` is checked before DNS servers**.

| File | Purpose |
|---|---|
| `/etc/hosts` | static name → IP overrides on this machine only (`192.168.56.10  almavm`) |
| `/etc/resolv.conf` | which DNS servers to ask (`nameserver 1.1.1.1`) and search domains |
| `/etc/hostname` | this machine's own name (`hostnamectl set-hostname web01`) |

- On AlmaLinux, `resolv.conf` is written by NetworkManager → change DNS with `nmcli con mod <con> ipv4.dns ...`, not by editing the file.
- **Ubuntu:** `systemd-resolved` manages it; check with `resolvectl status`.

### Record types
| Type | Maps | Example |
|---|---|---|
| A | name → IPv4 | `web01.example.com → 203.0.113.20` |
| AAAA | name → IPv6 | `web01.example.com → 2001:db8::20` |
| CNAME | alias → another name | `www.example.com → web01.example.com` |
| MX | domain → mail server (with priority) | `10 mail.example.com` |
| TXT | free text (SPF, domain verification) | `"v=spf1 include:_spf.google.com ~all"` |
| NS | which servers are authoritative | `ns1.provider.net` |
| PTR | IP → name (reverse DNS) | `20.113.0.203.in-addr.arpa → web01.example.com` |

### Tools
```bash
sudo dnf install -y bind-utils        # dig, nslookup, host (Ubuntu: apt install dnsutils)
dig example.com                       # full answer
dig +short example.com A
dig +short example.com MX
dig @8.8.8.8 example.com              # ask a specific server
dig -x 8.8.8.8 +short                 # reverse lookup
nslookup example.com
getent hosts almavm                   # uses nsswitch, so /etc/hosts entries show up too
```
(203.0.113.0/24 and 2001:db8::/32 are documentation ranges — placeholders, not real servers.)

TTL (seconds) in the dig answer = how long resolvers cache the record.

Script: [`scripts/dns_check.sh`](scripts/dns_check.sh)

---

## 5. Ports

A port identifies the service on a host (0–65535). 0–1023 are "well-known" (need root to bind). Clients use random ephemeral ports (Linux default 32768–60999).

| Port | Protocol | Service |
|---|---|---|
| 20, 21 | TCP | FTP |
| 22 | TCP | SSH / SCP / SFTP |
| 23 | TCP | Telnet (plain text, avoid) |
| 25 | TCP | SMTP |
| 53 | UDP/TCP | DNS |
| 67, 68 | UDP | DHCP |
| 80 | TCP | HTTP |
| 110 | TCP | POP3 |
| 123 | UDP | NTP |
| 143 | TCP | IMAP |
| 443 | TCP | HTTPS |
| 587 | TCP | SMTP submission |
| 3306 | TCP | MySQL / MariaDB |
| 3389 | TCP | RDP |
| 5432 | TCP | PostgreSQL |
| 6379 | TCP | Redis |
| 8080 | TCP | alt HTTP / app servers |
| 27017 | TCP | MongoDB |

Listening sockets and tests:
```bash
sudo ss -tulnp                       # TCP+UDP, listening, numeric, with process
sudo ss -tlnp | grep ':80'
curl -I http://localhost             # HTTP check
nc -zv 192.168.56.10 22              # is the port open? (dnf install nmap-ncat)
```

Script: [`scripts/port_check.sh`](scripts/port_check.sh)

---

## 6. Firewalls with firewalld (AlmaLinux)

firewalld groups rules into **zones**; each interface belongs to one zone (default `public`). Rules can be **services** (named, e.g. `http`) or raw **ports**.

```bash
sudo systemctl enable --now firewalld
sudo firewall-cmd --state
sudo firewall-cmd --get-default-zone
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --list-all                       # what's allowed in the active zone

sudo firewall-cmd --permanent --add-service=http   # --permanent = survives reboot
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --permanent --remove-service=cockpit
sudo firewall-cmd --reload                         # apply permanent rules

# SSH only from one IP (rich rule) — then remove the open ssh service
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="203.0.113.10/32" service name="ssh" accept'
sudo firewall-cmd --permanent --remove-service=ssh
```
⚠️ Do the SSH restriction from the VM console, or keep a second session open — easy to lock yourself out.

Without `--permanent` a rule is runtime-only (gone after reload/reboot) — handy for testing.

**SELinux + ports:** if a service listens on a non-standard port, SELinux must allow it too:
```bash
sudo semanage port -a -t http_port_t -p tcp 8081     # dnf install policycoreutils-python-utils
sudo semanage port -a -t ssh_port_t -p tcp 2222
```

- **Ubuntu:** `ufw` instead — `sudo ufw allow OpenSSH`, `sudo ufw allow 80,443/tcp`, `sudo ufw enable`, `sudo ufw status verbose`.

Script: [`scripts/firewall_setup.sh`](scripts/firewall_setup.sh)

---

## 7. Cloud security groups vs NACLs

| | Security Group (AWS) | Network ACL (AWS) |
|---|---|---|
| Applies to | instance / network interface | whole subnet |
| State | **stateful** — reply traffic is allowed automatically | **stateless** — reply traffic needs its own rule (ephemeral ports 1024–65535) |
| Rules | allow only | allow **and** deny |
| Evaluation | all rules together | numbered, lowest first, first match wins |
| Default | new SG: no inbound, all outbound | default NACL: allow all both ways |

(Azure's NSGs are also stateful but have allow/deny rules with priorities; GCP uses VPC firewall rules.)

### Example security group for a web server

| Direction | Type | Port | Source / Destination | Why |
|---|---|---|---|---|
| Inbound | SSH | 22 | `<my-public-ip>/32` | admin access from my IP only |
| Inbound | HTTP | 80 | `0.0.0.0/0` (+ `::/0`) | public website |
| Inbound | HTTPS | 443 | `0.0.0.0/0` (+ `::/0`) | public website (TLS) |
| Outbound | All | all | `0.0.0.0/0` | updates, package installs (AWS default) |

Find my public IP: `curl -s https://checkip.amazonaws.com`.

The same rules as AWS-style JSON: [`security-group-example.json`](security-group-example.json) — an **example** (the IDs and `203.0.113.10` are placeholders from the documentation range). Its `IpPermissions` array is the shape the AWS CLI takes:
```bash
aws ec2 authorize-security-group-ingress --group-id sg-XXXXXXXX \
  --ip-permissions "$(jq -c '.IpPermissions' security-group-example.json)"
```

**Defence in depth:** security group (cloud edge) + firewalld (on the VM) + SSH key-only login. If one is misconfigured, the others still protect the box.
