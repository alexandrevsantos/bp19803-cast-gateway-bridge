# BP19803 – Cast Gateway Bridge Setup

This repository contains a complete configuration and automation set to deploy a bridge-based gateway server for isolating Chromecast casting traffic in a multi-tenant VLAN environment.

## Features

- Shared IP subnet across guest and casting VLANs
- Layer 2 enforcement using `ebtables`
- DNS-only service via `dnsmasq`
- Netplan bridge configuration for Ubuntu 24.04 LTS
- Kernel and firewall tuning for secure casting
- Designed for native Google Cast SDK compatibility

## Contents

- `setup.sh`: Main installation script
- `bridge-init-ebtables.sh`: BPDU-blocking ebtables rule initializer
- `etc/`: Static configuration files
  - `dnsmasq.conf`: DNS config
  - `netplan/01-bridge.yaml`: Bridge with static IP
  - `systemd/bridge-ebtables.service`: Systemd unit to apply ebtables rules at boot

## Usage

Run:

```bash
sudo bash setup.sh
