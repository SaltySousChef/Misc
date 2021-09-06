#!/bin/bash

# install dependencies
cd ~/
sudo apt update
sudo apt install build-essential jq -y
sudo apt install expect -y
wget https://golang.org/dl/go1.17.linux-amd64.tar.gz
tar -xvf go1.17.linux-amd64.tar.gz
sudo mv go /usr/local
echo "" >> ~/.profile
echo 'export GOPATH=$HOME/go' >> ~/.profile
echo 'export GOROOT=/usr/local/go' >> ~/.profile
echo 'export GOBIN=$GOPATH/bin' >> ~/.profile
echo 'export PATH=$PATH:/usr/local/go/bin:$GOBIN' >> ~/.profile
rm go1.17.linux-amd64.tar.gz

# refresh env
. ~/.profile

# check paths are set
if [ -z "$GOPATH" ]
then
      echo "\$GOPATH not set! The environment was not configured correctly..."
      exit 1
fi

# install regen-cli
git clone https://github.com/regen-network/regen-ledger $GOPATH/src/github.com/regen-network/regen-ledger
cd $GOPATH/src/github.com/regen-network/regen-ledger
git fetch
git checkout v1.0.0
make install

# generate ~/.regen folder (regen-1 is the current the main chain)
regen init --chain-id regen-1 regen-validator

# add genesis file (required to create keys)
curl -s https://raw.githubusercontent.com/regen-network/mainnet/main/regen-1/genesis.json > ~/.regen/config/genesis.json

# create keychain with random base64 password and generate primary wallet
echo '#! /usr/bin/expect -f
set PASSWORD [lindex $argv 0];
spawn regen keys add regen-wallet
expect "Enter keyring passphrase:"
send -- "$PASSWORD\r"
expect "Re-enter keyring passphrase:"
send -- "$PASSWORD\r"
expect "$ "
' >> ~/key-maker.sh
chmod 755 ~/key-maker.sh
cd ~/
./key-maker.sh $(openssl rand -base64 12) >> wallet.txt
sed -i '1,2d' wallet.txt && sed -i 's/Re-enter keyring passphrase:/Keyring passphrase: /' wallet.txt

# backup config and wallet to google bucket
sudo gsutil cp -r ~/.regen/config $1
sudo gsutil cp ~/wallet.txt $1

# delete file containing private key and keychain password
rm wallet.txt

# update config with peers for main chain
sed -i 's/persistent_peers = ""/persistent_peers = "69975e7afdf731a165e40449fcffc75167a084fc@104.131.169.70:26656,d35d652b6cb3bf7d6cb8d4bd7c036ea03e7be2ab@116.203.182.185:26656,ffacd3202ded6945fed12fa4fd715b1874985b8c@3.98.38.91:26656"/' ~/.regen/config/config.toml

# the following line that changes localhost to 0.0.0.0 to expose the RPC port was written by regen
# in their deployment guide. I have added it but left it commented out as this doesn't seem like something we want. 
# sed -i 's#tcp://127.0.0.1:26657#tcp://0.0.0.0:26657#g' ~/.regen/config/config.toml

# enable prometheus
sed -i 's/prometheus = false/prometheus = true/' ~/.regen/config/config.toml

# add regen to systemctl and start syncing
echo "[Unit]
Description=regen daemon
After=network-online.target
[Service]
User=node_runner
ExecStart=/home/node_runner/go/bin/regen start
Restart=always
RestartSec=3
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
" >regen.service
sudo mv regen.service /lib/systemd/system/regen.service
sudo -S systemctl daemon-reload
sudo -S systemctl enable regen
sudo -S systemctl start regen

exit
