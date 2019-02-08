#!/bin/bash

API_IP=""
API_SERVER=""
HOST_NAME=""
MASTER_TOKEN=""
DISCOVERY_TOKEN=""

SHOW_USAGE="-a | --api-ip , -b | --api-server , -h | --host-name , -m | --master-token , -t | --discovery-token"
GETOPT_ARGS=`getopt -o a:b:h:m:t: -al api-ip:,api-server:,host-name:,master-token:,discovery-token: -- "$@"`
eval set -- "$GETOPT_ARGS"
while [ -n "$1" ]
	do
		case "$1" in
		        -a|--api-ip)          API_IP=$2; shift 2;;
		        -b|--api-server)      API_SERVER=$2; shift 2;;
		        -h|--host-name)       HOST_NAME=$2; shift 2;;
		        -m|--master-token)    MASTER_TOKEN=$2; shift 2;;
		        -t|--discovery-token) DISCOVERY_TOKEN=$2; shift 2;;
		        --) break ;;
		        *)  echo $1,$2,$SHOW_USAGE; break ;;
		esac
done

if [[ -z $API_IP || -z $API_SERVER || -z $HOST_NAME || -z $MASTER_TOKEN || -z $DISCOVERY_TOKEN ]]; then
	echo "参数错误，必传："$SHOW_USAGE
	exit 0
fi

#设置主机名
hostnamectl set-hostname ${HOST_NAME}
#设置hosts
echo "127.0.0.1  ${HOST_NAME}" >> /etc/hosts
echo "${API_IP}  ${API_SERVER}" >> /etc/hosts
#安装必要软件
yum install -y epel-release  net-tools wget vim \
		ntpdate bash-completion lrzsz unzip bridge-utils.x86_64
#初始化前准备
wget https://raw.githubusercontent.com/javac2005/k8s/master/aliyun/common/pre.sh
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
