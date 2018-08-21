#!/bin/bash -x

# resolve links - $0 may be a softlink
if [ -z "$LABS_HOME" ];then
  PRG="$0"
  while [ -h "$PRG" ] ; do
    ls=`ls -ld "$PRG"`
    link=`expr "$ls" : '.*-> \(.*\)$'`
    if expr "$link" : '/.*' > /dev/null; then
      PRG="$link"
    else
      PRG=`dirname "$PRG"`/"$link"
    fi
  done

  cd $(dirname $PRG)
  export LABS_HOME=`pwd`
  cd -&>/dev/null
fi

[ -z $LABS_HOME ] && exit 1
echo "HOME: $LABS_HOME"
################################################################################
# Define common variable
BIN_DIR=${BIN_DIR:-$LABS_HOME/bin}
MODULE_DIR=${MODULE_DIR:-$LABS_HOME/module}
AZURE_HOME=${AZURE_HOME:-$LABS_HOME/azure}
VAGRANT_BASE=${VAGRANT_BASE:-$LABS_HOME/vagrant}
# SSH
SSH_OPT=${SSH_OPT:-""}
################################################################################
# Create server
SERVER_TYPE="vagrant"
NUM_SERVER=${NUM_SERVER:-2}
IPS=()
SSH_BASE=2120
SSH_PORTS=()
ADMINS=()
HOSTNAME_PREFIX="node"

function setup_vagrant () {
  # TODO : install vagrant if not installed
  echo "set up vagrant.."
}
function create_vagrant () {
  INDEX=$1
  VAGRANT_HOME=${VAGRANT_BASE}${INDEX}
  VAGRANT_ORIGIN=${VAGRANT_BASE}/Vagrantfile
  VAGRANT_FILE=${VAGRANT_HOME}/Vagrantfile
  cd ${LABS_HOME}
  mkdir ${VAGRANT_HOME}
  SSH_PORT=$(($SSH_BASE+$INDEX))
  cat ${VAGRANT_ORIGIN} | sed -e "s/__SSH__/${SSH_PORT}/" >> ${VAGRANT_FILE}
  cd ${VAGRANT_HOME}
  vagrant up > /dev/null 2>$1
  IP=$(vagrant ssh -c "ifconfig eth1" | grep 'inet ' | awk '{print $2}')
  if [ -z ${IP} ]; then
    echo "network is full"
    exit
  fi
  IPS[$INDEX]=${IP}
  SSH_PORTS[$INDEX]=22 # host ssh port (2200+index is guest ssh port to host)
  ADMINS[$INDEX]=root
  cd ${LABS_HOME}
  ssh root@${IP} "reboot"
}
function create_servers () {
  setup="setup_${SERVER_TYPE}"
  eval ${setup}
  call_func="create_${SERVER_TYPE}"
  for i in $(seq 1 ${NUM_SERVER}); do
    # args : INDEX, 
    eval $call_func ${i}
  done
  sleep 30s
}
################################################################################
# Setup hostname for cluster
function setup_hostnames() {
  local HOSTNAMES=""
  for i in $(seq 1 ${NUM_SERVER}); do
    local IP=${IPS[i]}
    local HOSTNAME="${HOSTNAME_PREFIX}${i}"
    if [ ${i} -eq '1' ]; then
      HOSTNAME="k8s-master" 
    fi
    ssh ${SSH_OPT} -p ${SSH_PORTS[i]} ${ADMINS[i]}@${IPS[i]} "sudo sh -c 'hostnamectl set-hostname $HOSTNAME'"
    HOSTNAMES="${HOSTNAMES}${IP}  ${HOSTNAME}\\n"
  done
  echo -e "$HOSTNAMES"
  for i in $(seq 1 ${NUM_SERVER}); do
    ssh ${SSH_OPT} -p ${SSH_PORTS[i]} ${ADMINS[i]}@${IPS[i]} "sudo sh -c 'echo -e \"$HOSTNAMES\" >> /etc/hosts'"
  done
}

################################################################################
# Install softwares
CONFIG_FILE=${CONFIG_FILE:-$BIN_DIR/config}
function install_sw_servers () {
  # install master
  scp -r ${SSH_OPT} -P ${SSH_PORTS[1]} ${BIN_DIR} ${ADMINS[1]}@${IPS[1]}:.
  ssh ${SSH_OPT} -p ${SSH_PORTS[1]} ${ADMINS[1]}@${IPS[1]} << EOF
    sudo ./bin/install-kubernetes-master.sh
EOF
  # get token
  TOKEN=$(ssh ${SSH_OPT} -p ${SSH_PORTS[1]} ${ADMINS[1]}@${IPS[1]} "kubeadm token list" | tail -2 | awk '{ print $1 }')
  echo ${TOKEN}
  CA_CERT_HASH=$(ssh ${SSH_OPT} -p ${SSH_PORTS[1]} ${ADMINS[1]}@${IPS[1]} "openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -pubkey | openssl rsa -pubin -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1")
  echo ${CA_CERT_HASH}
  for i in $(seq 2 ${NUM_SERVER}); do
    scp -r ${SSH_OPT} -P ${SSH_PORTS[i]} ${BIN_DIR} ${ADMINS[i]}@${IPS[i]}:.
    ssh ${SSH_OPT} -p ${SSH_PORTS[i]} ${ADMINS[i]}@${IPS[i]} << EOF
      sudo ./bin/install-kubernetes-worker.sh -t ${TOKEN} -c ${CA_CERT_HASH}
EOF
  done
}

################################################################################
# create pod
function create_pod () {
  echo "create pod here.."
  ssh ${SSH_OPT} -p ${SSH_PORTS[1]} ${ADMINS[1]}@${IPS[1]} << EOF
    ./bin/create-pod.sh
EOF
}

################################################################################
function help () {
  echo "  -i : ssh solution team public key file for azure ($SSH_KEY)"
  echo "  -n : number of server (${NUM_SERVER})"
  echo "  -p : ssh solution team private key file for azure (${NUM_SERVER})"
  echo "  -s : type of server [vagrant|existing] ($SERVER_TYPE)"
  echo
}
# parse arguments
while getopts "i:n:p:s:h" FLAG; do
  case $FLAG in
    i) SSH_KEY=$OPTARG ;;
    n) NUM_SERVER=$OPTARG ;;
    p) SSH_PRIV=$OPTARG ;;
    s) SERVER_TYPE=$OPTARG ;;
    h|\?) help ; exit 1 ;;
  esac
done
shift $((OPTIND-1))

# set ssh
if [ ${SERVER_TYPE} == "azure" ]; then
  SSH_OPT="-i ${SSH_PRIV}"
fi
################################################################################
create_servers

[[ -e $CONFIG_FILE ]] && rm ${CONFIG_FILE} && touch ${CONFIG_FILE}

for i in $(seq 1 ${NUM_SERVER}); do
  echo "${IPS[$i]}" >> $CONFIG_FILE 
done

echo "Config file"
while read -r line; do echo "$line"; done < $CONFIG_FILE

setup_hostnames
install_sw_servers
create_pod

echo "Config file"
while read -r line; do echo "$line"; done < $CONFIG_FILE
