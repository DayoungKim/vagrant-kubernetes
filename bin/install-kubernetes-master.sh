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
# redhat/centos
# firewall
sudo systemctl disable firewalld
sudo systemctl stop firewalld
sudo modprobe br_netfilter
sudo echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables
# instsall kubernetes things
sudo cp ${SCRIPT_HOME}/kubernetes.repo /etc/yum.repos.d/kubernetes.repo
yum install -y kubectl docker kubeadm
systemctl restart docker && systemctl enable docker
systemctl restart kubelet && systemctl enable kubelet
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
MASTER_IP=$(head -n 1 ${SCRIPT_HOME}/config)
IFS=. read -r ip1 ip2 ip3 ip4 <<< "$MASTER_IP"
# run kubernetes master
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr ${ip1}.${ip2}.0.0/12 \
  --apiserver-advertise-address ${MASTER_IP} \
  --kubernetes-version v1.11.0
# move config file for kubectl
mkdir -p $HOME/.kube
echo "$HOME/.kube"
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
# install flannel : kuberentes plugin for cluster network
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.10.0/Documentation/kube-flannel.yml
# TODO : install dashboard : kubernetes cluster management ui
#kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
