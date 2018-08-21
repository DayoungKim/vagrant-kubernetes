#!/bin/bash
# resolve links - $0 may be a softlink
if [ -z "$SCRIPT_HOME" ];then
  PRG="$0"
  while [ -h "$PRG" ] ; do
    ls=`ls -ld "$PRG"`
    link=`expr "$ls" : '.*-\(.*\)$'`
    if expr "$link" : '/.*' /dev/null; then
      PRG="$link"
    else
      PRG=`dirname "$PRG"`/"$link"
    fi
  done
 
  cd $(dirname $PRG)
  export SCRIPT_HOME=`pwd`
  cd -&>/dev/null
fi
if [ -z $1 ]; then
  TARGET=$HOME
fi
TOKEN=${TOKEN:-""}
CA_CERT_HASH=${CA_CERT_HASH:-""}
function help () {
  echo "token : ${TOKEN}"
  echo "ca cert hash : ${CA_CERT_HASH}"
}
while getopts "c:t:h" FLAG; do
  case $FLAG in
    c) CA_CERT_HASH=$OPTARG ;;
    t) TOKEN=$OPTARG ;;
    h|\?) help ; exit 1 ;;
  esac
done
shift $((OPTIND-1))
if [ -z ${TOKEN} ]; then 
  exit
fi
if [ -z ${CA_CERT_HASH} ]; then
  exit
fi
echo "token : ${TOKEN}"
echo "ca cert hash : ${CA_CERT_HASH}"
# firewall
sudo systemctl disable firewalld
sudo systemctl stop firewalld
sudo modprobe br_netfilter
sudo echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables
# instsall kubectl
sudo cp ${SCRIPT_HOME}/kubernetes.repo /etc/yum.repos.d/kubernetes.repo
yum install -y docker kubeadm
systemctl restart docker && systemctl enable docker
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
MASTER_IP=$(head -n 1 ${SCRIPT_HOME}/config)
kubeadm join ${MASTER_IP}:6443 --token ${TOKEN} --discovery-token-ca-cert-hash sha256:${CA_CERT_HASH}
