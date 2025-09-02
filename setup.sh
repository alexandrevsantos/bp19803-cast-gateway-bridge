#!/bin/bash
set -e

echo "[+] Setting up bridge server for BP19803 architecture"

# 1. Netplan Configuration
echo "[+] Creating Netplan bridge configuration"
cat <EOF | sudo tee /etc/netplan/01-bridge.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: no
      dhcp6: no
    eth1:
      dhcp4: no
      dhcp6: no
  bridges:
    br0:
      interfaces: [eth0, eth1]
      addresses:
        - 10.200.0.1/20
      nameservers:
        addresses:
          - 127.0.0.1
          - 8.8.8.8
      dhcp4: no
      dhcp6: no
EOF

echo "[+] Applying Netplan"
sudo netplan apply

# 2. Kernel Command Line
echo "[+] Configuring kernel boot options"
sudo sed -i 's/^GRUB_CMDLINE_LINUX=.*$/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0 ipv6.disable=1 apparmor=0"/' /etc/default/grub
sudo update-grub

# 3. Disable UFW
echo "[+] Removing UFW firewall"
sudo systemctl stop ufw || true
sudo apt -y remove ufw || true

# 4. Install legacy iptables + ebtables
echo "[+] Installing iptables, ebtables, dnsmasq"
sudo apt update
sudo apt install -y iptables ebtables dnsmasq iptables-persistent

sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
sudo update-alternatives --set ebtables /usr/sbin/ebtables-legacy
sudo update-alternatives --set arptables /usr/sbin/arptables-legacy

# 5. Enable br_netfilter + sysctl bridge hooks
echo "[+] Enabling bridge netfilter sysctl settings"
sudo modprobe br_netfilter
cat <EOF | sudo tee /etc/sysctl.d/99-bridge-nf.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF
sudo sysctl --system

# 6. Configure dnsmasq (DNS only)
echo "[+] Configuring dnsmasq for split DNS"
sudo systemctl stop dnsmasq
cat <EOF | sudo tee /etc/dnsmasq.conf
interface=lo
bind-interfaces
listen-address=127.0.0.1
no-resolv
server=8.8.8.8
server=8.8.4.4
address=/cast.local/10.200.0.9
address=/bridge.local/10.200.0.1
server=/internal.example.com/10.200.0.1
EOF
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq

# 7. Create ebtables base rule script (drop BPDU)
echo "[+] Creating ebtables base rule script"
cat <'EOF' | sudo tee /usr/local/sbin/bridge-init-ebtables.sh
#!/bin/bash
ebtables -F
ebtables -A FORWARD -p 0x0003 -j DROP
ebtables -A INPUT -p 0x0003 -j DROP
ebtables -A OUTPUT -p 0x0003 -j DROP
EOF

sudo chmod +x /usr/local/sbin/bridge-init-ebtables.sh

# 8. Systemd unit to run ebtables at boot
echo "[+] Installing systemd unit for ebtables setup"
cat <EOF | sudo tee /etc/systemd/system/bridge-ebtables.service
[Unit]
Description=Apply ebtables base rules (BPDU blocking)
After=network-pre.target
Wants=network-pre.target
Before=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bridge-init-ebtables.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable bridge-ebtables.service
sudo systemctl start bridge-ebtables.service

# 9. Base iptables rules
echo "[+] Applying basic iptables policy"
sudo iptables -F
sudo iptables -A FORWARD -s 10.200.0.0/20 -d 10.200.0.0/20 -j DROP
sudo iptables -A INPUT -d 10.200.0.1 -j ACCEPT
sudo iptables -A OUTPUT -s 10.200.0.1 -j ACCEPT
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A OUTPUT -o lo -j ACCEPT
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables-save > /etc/iptables/rules.v4

sudo systemctl enable netfilter-persistent.service

echo "[✓] Setup complete. Reboot required to apply GRUB and network module changes."

