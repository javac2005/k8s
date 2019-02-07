#!/bin/bash

HOST_NAME=$1
API_SERVER=$2
API_IP=$3
MASTER_TOKEN=$4
DISCOVERY_TOKEN=$5

#设置主机名
hostnamectl set-hostname ${HOST_NAME}
#设置hosts
echo "127.0.0.1  ${HOST_NAME}" >> /etc/hosts
echo "${API_IP}  ${API_SERVER}" >> /etc/hosts
#安装必要软件
yum install -y epel-release  net-tools wget vim \
		ntpdate bash-completion lrzsz unzip bridge-utils.x86_64
#初始化前准备
wget https://raw.githubusercontent.com/javac2005/k8s/master/aliyun/pre.sh
chmod +x pre.sh
./pre.sh

#下载镜像
for imageName in \
	kube-proxy:v1.13.1 \
	coredns:1.2.6 \
	pause:3.1 \
	kubernetes-dashboard-amd64:v1.10.1; \
do \
	docker pull registry.cn-hangzhou.aliyuncs.com/google_containers/${imageName}; \
	docker tag registry.cn-hangzhou.aliyuncs.com/google_containers/${imageName} k8s.gcr.io/${imageName}; \
	docker rmi -f registry.cn-hangzhou.aliyuncs.com/google_containers/${imageName}; \
done

docker pull registry.cn-beijing.aliyuncs.com/common-registry/flannel:v0.10.0-amd64
docker tag registry.cn-beijing.aliyuncs.com/common-registry/flannel:v0.10.0-amd64 quay.io/coreos/flannel:v0.10.0-amd64
docker rmi -f registry.cn-beijing.aliyuncs.com/common-registry/flannel:v0.10.0-amd64

docker pull registry.cn-beijing.aliyuncs.com/common-registry/nginx-ingress-controller:0.21.0
docker tag registry.cn-beijing.aliyuncs.com/common-registry/nginx-ingress-controller:0.21.0 quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.21.0
docker rmi -f registry.cn-beijing.aliyuncs.com/common-registry/nginx-ingress-controller:0.21.0

#加入集群
kubeadm join ${API_SERVER}:6443 \
	--token ${MASTER_TOKEN} --discovery-token-ca-cert-hash \
	sha256:${DISCOVERY_TOKEN}
