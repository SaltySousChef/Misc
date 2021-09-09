#! /bin/bash

##############################################################
#
# Start with: sudo ./scan.sh <target-ip> <rpc-port> <p2p-port>
#
##############################################################

export IP=$1
export RPC_PORT=$2
export P2P_PORT=$3

export CVE_LINK='Scan complete. Review any discoveries in the CVE database: https://cve.mitre.org/cve/search_cve_list.html'

if ! command -v nmap &> /dev/null
then
    echo "nmap could not be found"
    echo "Install with 'apt install nmap' on linux or 'bew install nmap' on mac"
    exit
fi

if ! command -v sslscan &> /dev/null
then
    echo "sslscan could not be found"
    echo "Install with 'apt install sslscan' on linux or 'bew install sslscan' on mac"
    exit
fi

if ! command -v hping3 &> /dev/null
then
    echo "hping3 could not be found"
    echo "Install with 'apt install hping3' on linux or 'bew install hping' on mac"
    exit
fi

echo ""
echo "Starting TCP stealth scan..."
sudo nmap -sS -sV -T4 -O -p 1-1000,$RPC_PORT,$P2P_PORT $IP
echo ""
echo "$CVE_LINK"
echo ""
read -p "Press enter to continue"

echo ""
echo "Starting TCP connect scan..."
sudo nmap -sT -sV -T4 -O -p 1-1000,$RPC_PORT,$P2P_PORT $IP
echo ""
echo "$CVE_LINK"
echo ""
read -p "Press enter to continue"

echo ""
echo "Starting SCTP INIT scan..."
sudo nmap -sY -sV -T4 -O -p 9,22,$RPC_PORT,$P2P_PORT $IP
echo ""
echo "$CVE_LINK"
echo ""
echo "(Results showing as filtered can be ignored)"
echo ""
read -p "Press enter to continue"

echo ""
echo "Starting UDP scan..."
sudo nmap -sU -sV -T4 -O -p 512-520,533-544,1759,$RPC_PORT,$P2P_PORT $IP
echo ""
echo "$CVE_LINK"
echo ""
echo "(Results showing as open|filtered imply request was dropped and nmap is not sure whether it is open or filtered)"
echo ""
read -p "Press enter to continue"

echo ""
echo "Starting TCP NULL scan..."
sudo nmap -sN -sV -T4 -p 1-1000,$RPC_PORT,$P2P_PORT $IP
echo ""
echo "$CVE_LINK"
echo ""
read -p "Press enter to continue"

echo ""
echo "Starting TCP FIN scan..."
sudo nmap -sF -sV -T4 -p 1-1000,$RPC_PORT,$P2P_PORT $IP
echo ""
echo "$CVE_LINK"
echo ""
read -p "Press enter to continue"

echo ""
echo "Starting XMAS scan..."
sudo nmap -sX -sV -T4 -p 1-1000,$RPC_PORT,$P2P_PORT $IP
echo ""
echo "$CVE_LINK"
echo ""
read -p "Press enter to continue"

echo ""
echo "Starting TCP ACK scan..."
sudo nmap -sA -sV -T4 -p 1-1000,$RPC_PORT,$P2P_PORT $IP
echo ""
echo "$CVE_LINK"
echo ""
read -p "Press enter to continue"

echo ""
echo "Starting SSL scan on P2P port..."
sslscan $IP:$P2P_PORT
echo ""
echo "$CVE_LINK"
echo ""
read -p "Press enter to continue"

echo ""
echo "Sending 100 SYN requests to P2P port..."
sudo hping3 -S $IP -p $P2P_PORT -c 100 --fast
echo ""
echo "Ideally these should be getting lost"
echo ""
read -p "Press enter to continue"

echo ""
echo "Sending 100 NULL requests to P2P port..."
sudo hping3 $IP -p $P2P_PORT -c 100 --fast
echo ""
echo "Ideally these should be getting lost"
echo ""
read -p "Press enter to continue"

echo ""
echo "Running traceroute..."
hping3 --traceroute -V -1 $IP
echo ""

echo "Scan finished!"

exit
