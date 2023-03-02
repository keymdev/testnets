#!/bin/bash
set -e

command_exists () {
    type "$1" &> /dev/null ;
}

function run_as_root() {
  if [ $EUID -eq 0 ]; then
    ($@)
  else
    (sudo $@)
  fi
}

if command_exists go ; then
    echo "Golang is already installed"
else
  echo "Install dependencies"
  run_as_root apt update
  run_as_root apt install build-essential jq wget git -y

  wget https://dl.google.com/go/go1.19.linux-amd64.tar.gz
  tar -xvf go1.19.linux-amd64.tar.gz
  run_as_root mv go /usr/local

  echo "" >> ~/.bashrc
  echo 'export GOPATH=$HOME/go' >> ~/.bashrc
  echo 'export GOROOT=/usr/local/go' >> ~/.bashrc
  echo 'export GOBIN=$GOPATH/bin' >> ~/.bashrc
  echo 'export PATH=$PATH:/usr/local/go/bin:$GOBIN' >> ~/.bashrc
  
fi

source ~/.bashrc
export GOPATH=$HOME/go
export GOROOT=/usr/local/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:/usr/local/go/bin:$GOBIN

echo "CAUTION!"
echo "-- If keytom was previously installed, the following step will remove ~/.keytomd from your system. Are you sure you would like to continue?--"

select yn in "Yes" "No"; do
    case $yn in
        Yes ) rm -rf ~/.keytomd; break;;
        No ) exit;;
    esac
done

DAEMON=keytomd
DENOM=akeym
CHAIN_ID=keym_2313-1
PERSISTENT_PEERS="1fbd24a5e3aac661ce09a880b0a125af4389ec55@65.109.113.176:26656"

echo "install keytom"
rm -rf ~/keytom.chain
git clone https://github.com/keymdev/keytom.chain
cd ~/keytom.chain
git fetch
git checkout master
go build -o keytomd ./cmd/keytomd
mkdir -p $GOBIN
cp keytomd $GOBIN/keytomd


echo "Keytom Chain has been installed succesfully!"
echo ""
echo "-- Next we will need to set up your keys and moniker"
echo "-- Please choose a name for your key --"
read YOUR_KEY_NAME

echo "-- Please choose a moniker --"
read YOUR_NAME

echo "-- Your Key Name is ${YOUR_KEY_NAME} and your moniker is ${YOUR_NAME}. Is this correct?"

select yn in "Yes" "No" "Cancel"; do
    case $yn in
        Yes ) break;;
        No ) echo "-- Please choose a name for your key --";
             read YOUR_KEY_NAME;
             echo "-- Please choose a moniker --";
             read YOUR_NAME; break;;
        Cancel ) exit;;
    esac
done

echo "-- Your Key Name is ${YOUR_KEY_NAME} and your moniker is ${YOUR_NAME}. --"

echo "Creating keys"
${DAEMON} keys add ${YOUR_KEY_NAME}

echo ""
echo "After you have copied the mnemonic phrase in a safe place,"
echo "press the space bar to continue."
read -s -d ' '
echo ""

echo "----------Setting up your validator node------------"
${DAEMON} init --chain-id $CHAIN_ID $YOUR_NAME
echo "------Downloading Keytom ChainTestnet genesis--------"
curl -s https://raw.githubusercontent.com/keymdev/testnets/master/keym_2313-1/genesis.json  > ~/.keytomd/config/genesis.json
echo "----------Setting config for seed node---------"
sed -i 's#tcp://127.0.0.1:26657#tcp://0.0.0.0:26657#g' ~/.${DAEMON}/config/config.toml
sed -i '/persistent_peers =/c\persistent_peers = "'"${PERSISTENT_PEERS}"'"' ~/.${DAEMON}/config/config.toml

DAEMON_PATH=$(which ${DAEMON})

echo "Installing cosmovisor - an upgrade manager..."

rm -rf $GOPATH/src/github.com/cosmos/cosmos-sdk
git clone https://github.com/cosmos/cosmos-sdk $GOPATH/src/github.com/cosmos/cosmos-sdk
cd $GOPATH/src/github.com/cosmos/cosmos-sdk
git checkout v0.45.4
cd cosmovisor
make cosmovisor
cp cosmovisor $GOBIN/cosmovisor

echo "Setting up cosmovisor directories"
mkdir -p ~/.keytomd/cosmovisor/genesis/bin
cp $GOBIN/keytomd ~/.keytomd/cosmovisor/genesis/bin

echo "---------Creating system file---------"

echo "[Unit]
Description=Cosmovisor daemon
After=network-online.target
[Service]
Environment="DAEMON_NAME=keytomd"
Environment="DAEMON_HOME=${HOME}/.${DAEMON}"
Environment="DAEMON_RESTART_AFTER_UPGRADE=on"
User=${USER}
ExecStart=${GOBIN}/cosmovisor start
Restart=always
RestartSec=3
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target
" >cosmovisor.service

run_as_root mv cosmovisor.service /lib/systemd/system/cosmovisor.service
run_as_root systemctl daemon-reload
run_as_root systemctl start cosmovisor

echo ""
echo "--------------Congratulations---------------"
echo ""
echo "View your account address by typing your passphrase below." 
chainAddr="$(${DAEMON} keys show ${YOUR_KEY_NAME} -a)"
echo "Native address: ${chainAddr}"
evmAddr="$(${DAEMON} debug addr ${chainAddr} | grep 'Address (hex)' | sed 's/Address (hex): /0x/')"
echo "Evm address: ${evmAddr}"
echo ""
echo ""
echo "Next you will need to fund the above wallet address. When finished, you can create your validator by customizing and running the following command"
echo ""
echo "keytomd tx staking create-validator --amount 1000000${DENOM} --commission-max-change-rate \"0.1\" --commission-max-rate \"0.20\" --commission-rate \"0.1\" --details \"Some details about yourvalidator\" --from <keyname> --pubkey=\"$(keytomd tendermint show-validator)\" --moniker <your moniker> --min-self-delegation \"1\" --chain-id ${CHAIN_ID} --gas auto --fees 500${DENOM}"
