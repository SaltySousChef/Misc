#! /usr/bin/expect -f

# Requires expect to be installed

# Configuration
set SEED "guilt comic fruit twist depend genuine label dune math chef assault mix aspect arrest civil grace card train setup original butter fever arena endorse"
set PASSWORD "5acbbasdasd7W++xhsdaasdMYU1asdask"
set WALLET_NAME "unique-name"
set AMOUNT_TO_STAKE_IN_UREGEN "2000000000uregen"
set COMMISION_RATE "0.10"
set COMMISION_RATE_MAX "0.20"
set COMMISION_RATE_CHANGE "0.01"
set MIN_DELEGATION "1"

# Add the key to key chain
spawn regen keys add $WALLET_NAME --recover
expect "Enter your bip39 mnemonic"
send -- "$SEED\r"
expect "Enter keyring passphrase:"
send -- "$PASSWORD\r"
expect "$ "

# Start the validator (needs to be fully synced)
# To get the value for pubkey run $regen tendermint show-validator
spawn regen tx staking create-validator --amount=$AMOUNT_TO_STAKE_IN_UREGEN \
  --pubkey=regenvalconspub1zcjduepqcaq3rusg5hm8tsee28vu3hw97jzgzmy8fcqdy6cwrtyu6mptwqfqewzgun \
  --moniker="regen-validator" \
  --chain-id=regen-1 \
  --commission-rate=$COMMISION_RATE \
  --commission-max-rate=$COMMISION_RATE_MAX \
  --commission-max-change-rate=$COMMISION_RATE_CHANGE \
  --min-self-delegation=$MIN_DELEGATION \
  --gas="auto" \
  --from=$WALLET_NAME
expect "Enter keyring passphrase:"
send -- "$PASSWORD\r"
expect "$ "
