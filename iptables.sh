#!/bin/bash

echo "Updating iptables configuration. This may take a few minutes..."

echo "Setting up SYNPROXY to mitigate SYN flood attacks"
sudo iptables -t raw -A PREROUTING -p tcp -m tcp --syn -j CT --notrack 
sudo iptables -A INPUT -p tcp -m tcp -m conntrack --ctstate INVALID,UNTRACKED -j SYNPROXY --sack-perm --timestamp --wscale 7 --mss 1460 -d 9651
sudo iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

echo "Blocking invalid packets"
sudo iptables -t mangle -A PREROUTING -m conntrack --ctstate INVALID -j DROP

echo "Blocking new packets that are not SYN"
sudo iptables -t mangle -A PREROUTING -p tcp ! --syn -m conntrack --ctstate NEW -j DROP

echo "Blocking requests with uncommon Maximum Segment Size (MMS)"
sudo iptables -t mangle -A PREROUTING -p tcp -m conntrack --ctstate NEW -m tcpmss ! --mss 536:65535 -j DROP

echo "Blocking packets with bogus TCP flags"
sudo iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,SYN FIN,SYN -j DROP
sudo iptables -t mangle -A PREROUTING -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
sudo iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
sudo iptables -t mangle -A PREROUTING -p tcp --tcp-flags FIN,ACK FIN -j DROP
sudo iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,URG URG -j DROP
sudo iptables -t mangle -A PREROUTING -p tcp --tcp-flags ACK,PSH PSH -j DROP
sudo iptables -t mangle -A PREROUTING -p tcp --tcp-flags ALL NONE -j DROP

# echo "Blocking requests from private subnets"
# sudo iptables -t mangle -A PREROUTING -s 224.0.0.0/3 -j DROP
# sudo iptables -t mangle -A PREROUTING -s 172.16.0.0/12 -j DROP 
# sudo iptables -t mangle -A PREROUTING -s 192.0.2.0/24 -j DROP 
# sudo iptables -t mangle -A PREROUTING -s 192.168.0.0/16 -j DROP 
# sudo iptables -t mangle -A PREROUTING -s 10.0.0.0/8 -j DROP 
# sudo iptables -t mangle -A PREROUTING -s 0.0.0.0/8 -j DROP 
# sudo iptables -t mangle -A PREROUTING -s 240.0.0.0/5 -j DROP 
# sudo iptables -t mangle -A PREROUTING -s 127.0.0.0/8 ! -i lo -j DROP

echo "Blocking ICMP packets"
sudo iptables -t mangle -A PREROUTING -p icmp -j DROP

echo "Blocking fragmented requests"
sudo iptables -t mangle -A PREROUTING -f -j DROP

echo "Blocking port scanners"
sudo iptables -N port-scanning 
sudo iptables -A port-scanning -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s --limit-burst 2 -j RETURN 
sudo iptables -A port-scanning -j DROP

echo "Applying rate limit for new connections"
sudo iptables -A INPUT -p tcp -m conntrack --ctstate NEW -m limit --limit 60/s --limit-burst 20 -j ACCEPT 
sudo iptables -A INPUT -p tcp -m conntrack --ctstate NEW -j DROP

echo "Mitigating TCP RST flood attacks"
sudo iptables -A INPUT -p tcp --tcp-flags RST RST -m limit --limit 2/s --limit-burst 2 -j ACCEPT 
sudo iptables -A INPUT -p tcp --tcp-flags RST RST -j DROP

echo "Settings updated!"
exit
