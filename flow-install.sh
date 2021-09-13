#! /bin/bash -i

##############################################################
# 
# Start with: ./flow.sh <node-role> <service-uri-subdomain> <service-uri-domain> <cloudflare-email-address> <cloudflare-zone> <cloudflare-key> <gs-bucket-url>
#
# <node-role> can be: access, collection, consensus, execution or verification
#
##############################################################

export NODE_ROLE=$1
export SUBDOMAIN=$2
export DOMAIN=$3
export CLOUDFLARE_EMAIL_ADDRESS=$4
export CLOUDFLARE_ZONE=$5
export CLOUDFLARE_KEY=$6
export GS_BUCKET_URL=$7

# configure local firewall
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22,3569/tcp

if [ "$NODE_ROLE" == "access" ] || [ "$NODE_ROLE" == "collection" ] || [ "$NODE_ROLE" == "execution" ]
then
    echo "Opening port 9000 for $NODE_ROLE node"
    sudo ufw allow 9000/tcp
elif [ "$NODE_ROLE" == "consensus" ] || [ "$NODE_ROLE" == "verification" ]
then
    echo "Port 9000 not required for $NODE_ROLE node"
else
    echo "NODE_ROLE environment variable does not match a valid option"
    exit
fi

# create dns record and add proxy
export DNS_ID="$(curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE/dns_records" \
     -H "X-Auth-Email: $CLOUDFLARE_EMAIL_ADDRESS" \
     -H "Authorization: Bearer $CLOUDFLARE_KEY" \
     -H "Content-Type:application/json"\
     --data '{"type":"A","name":"'"$SUBDOMAIN"'","content":"'"$(curl ifconfig.me)"'","proxied":true}' | jq -r '.result.id')"

# install dependencies
sudo apt update
sudo apt install build-essential libssl-dev -y

# install go
cd /tmp
sudo rm -rf /usr/local/go
wget https://golang.org/dl/go1.17.linux-amd64.tar.gz
tar -xvf go1.17.linux-amd64.tar.gz
sudo mv go /usr/local
echo "" >> ~/.bashrc
echo 'export GOPATH=$HOME/go' >> ~/.bashrc
echo 'export GOROOT=/usr/local/go' >> ~/.bashrc
echo 'export GOBIN=$GOPATH/bin' >> ~/.bashrc
echo 'export PATH=$PATH:/usr/local/go/bin:$GOBIN' >> ~/.bashrc
source ~/.bashrc

# build cmake
wget https://github.com/Kitware/CMake/releases/download/v3.20.0/cmake-3.20.0.tar.gz
tar -zxvf cmake-3.20.0.tar.gz
cd cmake-3.20.0
./bootstrap
make
sudo make install

# download node bootstrap
cd ~/
curl -sL -O storage.googleapis.com/flow-genesis-bootstrap/boot-tools.tar
tar -xvf boot-tools.tar

# confirm keys match intended origin
if [ "$(sha256sum ./boot-tools/bootstrap)" != "4f7034f6977fd1fc0980a2a38640db8d085714f7d928a67365a083886cb85814  ./boot-tools/bootstrap" ]
then
    echo "Boot-tools bootstrap sha256sum doesn't match!"
    exit
elif [ "$(sha256sum ./boot-tools/transit)" != "d1ef25d67fe339e4ae5bff150fdf814e66dba3e490965d4bb965ed34ea181e03  ./boot-tools/transit" ]
then
    echo "Boot tools transit sha256sum doesn't match!"
    exit
fi

# generate keys
mkdir ./bootstrap
./boot-tools/bootstrap key --address \"$SUBDOMAIN.$DOMAIN:3569\" --role $NODE_ROLE -o ./bootstrap

# upload public keys
./boot-tools/transit push -b ./bootstrap -t mainnet-12-$SUBDOMAIN -r $NODE_ROLE

# backup node credentials
mkdir $SUBDOMAIN &&  cp -r ~/bootstrap/. $SUBDOMAIN
sudo gsutil cp -r $SUBDOMAIN $GS_BUCKET_URL
rm -rf $SUBDOMAIN

# install flow-go
git clone https://github.com/onflow/flow-go && cd flow-go
git pull origin master

# clone submodules
git submodule update --init --recursive

# build
make install-tools

# configure systemd
sudo cp deploy/systemd-docker/flow-$NODE_ROLE.service /etc/systemd/system
sudo mkdir /etc/flow
sudo cp deploy/systemd-docker/runtime-conf.env /etc/flow

# start flow
sudo systemctl enable flow-$NODE_ROLE.service

echo "Setup complete!"
echo ""
echo "To connect to the main chain contact the flow team and request a PULL_TOKEN"
echo ""
echo "Once you have the token run: ./boot-tools/transit pull -b ./bootstrap -t <pull-token> -r $NODE_ROLE"
echo ""
echo "Then you can start staking with your wallet at https://port.onflow.org/ using the infomation contained in node-info.pub.*.json which is now in you gs bucket"

exit
