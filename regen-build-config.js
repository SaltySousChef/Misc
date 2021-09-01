// Machine spec - https://github.com/regen-network/mainnet/blob/2c22d677f769a7c8dd86a75cd8cdead9e576b734/regen-1/README.md#Requirements
const regenBuildConfig = {
  regen: {
    os: "projects/ubuntu-os-cloud/global/images/ubuntu-1804-bionic-v20210825",
    diskSizeGb: 200,
    machineType: "n2-standard-2", // Custom 2 CPU with 8GB RAM should be adequate (example is 4 CPU/8GB)
    ports: ["allow-26656"],
    metrics: [
      "127.0.0.1:26660/metrics", // Prometheus endpoint. Queries don't seem to work.
      "localhost:26657/status", // Status RPC endpoint seems to have most of the info in a JSON.
      "localhost:26657/net_info", // Peer count available here.
    ],
  },
};

// Need to change data dump location (gs://node-data-dev/) before test deployment.
const regenStartScript = `
#!/bin/bash

# wallet name is regen-wallet
# validator name is regen-validator
# password is generated at run time
# backup sent to gs://node-data-dev/

# stop script overwriting install after first boot
if [[ -f /etc/first_run_check ]]; then exit 0; fi
touch /etc/first_run_check

# stop on errors
set -e

# create node_runner user
sudo useradd -m node_runner
sudo usermod -aG sudo -s /bin/bash node_runner
sudo adduser node_runner sudo
sudo sh -c  "echo 'node_runner ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers"

# configure local firewall
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22,26656,26657/tcp

# run startup script as node_runner
sudo -u node_runner bash << EOF

    # go home to escape root
    cd ~/

    # install go (double escape on variables required to get them all the way there intact)
    sudo apt update
    sudo apt install build-essential jq -y
    wget https://dl.google.com/go/go1.15.6.linux-amd64.tar.gz
    tar -xvf go1.15.6.linux-amd64.tar.gz
    sudo mv go /usr/local
    echo "" >> ~/.profile
    echo 'export GOPATH=\\$HOME/go' >> ~/.profile
    echo 'export GOROOT=/usr/local/go' >> ~/.profile
    echo 'export GOBIN=\\$GOPATH/bin' >> ~/.profile
    echo 'export PATH=\\$PATH:/usr/local/go/bin:\\$GOBIN' >> ~/.profile
    
    # refresh session to use go paths
    . ~/.profile

    # install regen-cli
    git clone https://github.com/regen-network/regen-ledger \\$GOPATH/src/github.com/regen-network/regen-ledger
    cd \\$GOPATH/src/github.com/regen-network/regen-ledger
    git fetch
    git checkout v1.0.0
    make install

    # init the validator
    regen init --chain-id regen-1 regen-validator

    # add genesis file (required to create keys)
    curl -s https://raw.githubusercontent.com/regen-network/mainnet/main/regen-1/genesis.json > ~/.regen/config/genesis.json

    # create keychain with random base64 password and generate primary wallet
    sudo apt install expect -y
    echo '#! /usr/bin/expect -f
    set PASSWORD [lindex \\$argv 0];
    spawn /home/node_runner/go/bin/regen keys add regen-wallet
    expect "Enter keyring passphrase:"
    send -- "\\$PASSWORD\\r"
    expect "Re-enter keyring passphrase:"
    send -- "\\$PASSWORD\\r"
    expect "$ "
    ' >> ~/key-maker.sh
    chmod 755 ~/key-maker.sh
    cd ~/
    ./key-maker.sh $(openssl rand -base64 12) >> wallet.txt
    sed -i '1,2d' wallet.txt && sed -i 's/Re-enter keyring passphrase:/Keyring passphrase: /' wallet.txt

    # backup config and wallet to google bucket
    sudo gsutil cp -r /home/node_runner/.regen/config gs://node-data-dev
    sudo gsutil cp /home/node_runner/wallet.txt gs://node-data-dev

    # delete file containing private key and keychain password
    rm wallet.txt

    # update config with peers for main chain
    sed -i '/persistent_peers =/c\persistent_peers = "69975e7afdf731a165e40449fcffc75167a084fc@104.131.169.70:26656,d35d652b6cb3bf7d6cb8d4bd7c036ea03e7be2ab@116.203.182.185:26656,ffacd3202ded6945fed12fa4fd715b1874985b8c@3.98.38.91:26656"' /home/node_runner/.regen/config/config.toml

    # the following line that changes localhost to 0.0.0.0 to expose the RPC port was written by regen
    # in their deployment guide. I have added it but left it commented out as this doesn't seem like something we want. 
    # sed -i 's#tcp://127.0.0.1:26657#tcp://0.0.0.0:26657#g' /home/node_runner/.regen/config/config.toml
    
    # enable prometheus
    sed -i 's/prometheus = false/prometheus = true/' /home/node_runner/.regen/config/config.toml
    
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

EOF`;

// Node needs to be fully synced before running this command
// to avoid being jailed.
//
// Minimum to stake is 9000000 uregen.
const startValidatorCmd = `
regen tx staking create-validator \
  --amount=9000000uregen \
  --pubkey=$(regen tendermint show-validator) \
  --moniker="regen-validator" \
  --chain-id=regen-1 \
  --commission-rate="0.10" \
  --commission-max-rate="0.20" \
  --commission-max-change-rate="0.01" \
  --min-self-delegation="1" \
  --gas="auto" \
  --from=regen-wallet`;

export { regenBuildConfig, regenStartScript, startValidatorCmd };
