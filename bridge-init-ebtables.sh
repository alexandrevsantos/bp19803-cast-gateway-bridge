#!/bin/bash
ebtables -F
ebtables -A FORWARD -p 0x0003 -j DROP
ebtables -A INPUT -p 0x0003 -j DROP
ebtables -A OUTPUT -p 0x0003 -j DROP
