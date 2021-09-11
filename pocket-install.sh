#! /bin/bash -i

##############################################################
#
# Start with: ./poacket.sh <subdomain> <service-uri> <cloudflare-email-address> <cloudflare-zone> <cloudflare-key> <gs-bucket-url>
#
##############################################################

export SUBDOMAIN=$1
export SERVICE_URI=$2
export CLOUDFLARE_EMAIL_ADDRESS=$3
export CLOUDFLARE_ZONE=$4
export CLOUDFLARE_KEY=$5
export GS_BUCKET_URL=$6

# install dependencies
sudo apt update
sudo apt install expect nginx certbot python3-certbot-nginx -y

# configure dns record
export IP="$(curl ifconfig.me)"
curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE/dns_records" \
     -H "X-Auth-Email: $CLOUDFLARE_EMAIL_ADDRESS" \
     -H "Authorization: Bearer $CLOUDFLARE_KEY" \
     -H "Content-Type:application/json"\
     --data '{"type":"A","name":"'"$SUBDOMAIN"'","content":"'"$IP"'","proxied":true}'

# install go and add go paths to
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
rm go1.17.linux-amd64.tar.gz

# install pocket cli
mkdir -p $GOPATH/src/github.com/pokt-network && cd $GOPATH/src/github.com/pokt-network
git clone https://github.com/pokt-network/pocket-core.git && cd pocket-core
git checkout tags/RC-0.6.3.6
go build -o $GOPATH/bin/pocket $GOPATH/src/github.com/pokt-network/pocket-core/app/cmd/pocket_core/main.go

# create wallet with random base64 password
echo '#! /usr/bin/expect -f
set PASSWORD [lindex $argv 0];
spawn pocket accounts create
expect "Enter Passphrase:"
send -- "$PASSWORD\r"
expect "Enter passphrase again:"
send -- "$PASSWORD\r"
expect "$ "
spawn echo "Decrypt password: $PASSWORD"
expect "$ "
' >> ~/key-maker.sh
chmod +x ~/key-maker.sh
cd ~/
./key-maker.sh $(openssl rand -base64 12) >> wallet.txt && sed -i '1,4d;6d' wallet.txt 

# export the private key
echo "Encrypt password: $(openssl rand -base64 12)" >> wallet.txt
echo '#! /usr/bin/expect -f
set ADDRESS [lindex $argv 0];
set DECRYPT_PASSWORD [lindex $argv 1];
set ENCRYPT_PASSWORD [lindex $argv 1];
spawn pocket accounts export $ADDRESS
expect "Enter Decrypt Passphrase"
send -- "$DECRYPT_PASSWORD\r"
expect "Enter Encrypt Passphrase"
send -- "$ENCRYPT_PASSWORD\r"
expect "Enter an optional Hint for remembering the Passphrase"
send -- "\r"
expect "$ "
' >> ~/private-key-fetcher.sh
chmod +x ~/private-key-fetcher.sh
./private-key-fetcher.sh $(sed 's/\r//;s/Address: //;1q;d;' wallet.txt) $(sed 's/Decrypt password: //;2q;d;' wallet.txt) $(sed 's/Encrypt password: //;3q;d;' wallet.txt) >> /dev/null

# copy credentials to gs bucket
sudo gsutil cp ~/*.json $GS_BUCKET_URL
sudo gsutil cp wallet.txt $GS_BUCKET_URL

# remove records
rm ~/*.txt ~/*.json

# enable prometheus
sed -i 's/"Prometheus": false,/"Prometheus": true,/' ~/.pocket/config/config.json

# create relay chain config
echo "[
    {
        \"id\": \"0004\",
        \"url\": \"https://<rpc-username>:<rpc-password>@example.com\",
        \"basic_auth\": {
        \"username\": \"\",
        \"password\": \"\"
        }
    }
]" >> ~/.pocket/config/chains.json

# create temp ssl keys 
sudo openssl req -x509 -newkey rsa:4096 -keyout /etc/nginx/key.pem -out /etc/nginx/cert.pem -days 365 -nodes -subj "/C=US/ST=NY/L=NY/O=NA/OU=NA/CN=$SUBDOMAIN.$SERVICE_URI/emailAddress=$CLOUDFLARE_EMAIL_ADDRESS"

# add server block to nginx - ssl_certificate and key location will be rewritten by cert bot
sudo sed -i '/include \/etc\/nginx\/sites-enabled\// a \
        \
        server {\
            listen              443 ssl;\
            server_name         '"$SUBDOMAIN.$SERVICE_URI"';\
            ssl_certificate     \/etc\/nginx\/cert.pem;\
            ssl_certificate_key \/etc\/nginx\/key.pem;\
            location \/ {\
                proxy_pass http:\/\/localhost:8081;\
            }\
        }' /etc/nginx/nginx.conf

# setup ssl certificate and populate nginx config
sudo certbot --nginx -d $SUBDOMAIN.$SERVICE_URI -n

# add cron job to check daily if the cert needs to be updated
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

# set max files
ulimit -Sn 16384

# start node
pocket start --seeds="03b74fa3c68356bb40d58ecc10129479b159a145@seed1.mainnet.pokt.network:20656,64c91701ea98440bc3674fdb9a99311461cdfd6f@seed2.mainnet.pokt.network:21656,0057ee693f3ce332c4ffcb499ede024c586ae37b@seed3.mainnet.pokt.network:22856,9fd99b89947c6af57cd0269ad01ecb99960177cd@seed4.mainnet.pokt.network:23856,f2a4d0ec9d50ea61db18452d191687c899c3ca42@seed5.mainnet.pokt.network:24856,f2a9705924e8d0e11fed60484da2c3d22f7daba8@seed6.mainnet.pokt.network:25856,582177fd65dd03806eeaa2e21c9049e653672c7e@seed7.mainnet.pokt.network:26856,2ea0b13ab823986cfb44292add51ce8677b899ad@seed8.mainnet.pokt.network:27856,a5f4a4cd88db9fd5def1574a0bffef3c6f354a76@seed9.mainnet.pokt.network:28856,d4039bd71d48def9f9f61f670c098b8956e52a08@seed10.mainnet.pokt.network:29856,5c133f07ed296bb9e21e3e42d5f26e0f7d2b2832@poktseed100.chainflow.io:26656,361b1936d3fbe516628ebd6a503920fc4fc0f6a7@seed.pokt.rivet.cloud:26656" --mainnet

EOF

exit
