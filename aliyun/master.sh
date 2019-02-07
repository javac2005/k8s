#!/bin/bash

HOSTS=($1)
API_SERVER=$2
NAMES=(master0 master1 master2)

rm -rf /etc/kubernetes

#配置本机hosts
for i in "${!HOSTS[@]}"; do
	echo "${HOSTS[$i]}  ${NAMES[$i]}" >> /etc/hosts
done

#生成密钥，做免密登录
ssh-keygen -t rsa
for i in "${!HOSTS[@]}"; do
	ssh-copy-id ${NAMES[$i]}
done

#配置hosts
for i in "${!HOSTS[@]}"; do
	ssh ${NAMES[$i]} "hostnamectl set-hostname ${NAMES[$i]}"
	ssh ${NAMES[$i]} "echo ${HOSTS[$j]}  ${API_SERVER} >> /etc/hosts"
	if [[ ${NAMES[$i]} != ${NAMES[0]} ]]
		then
		for j in "${!HOSTS[@]}"; do
		ssh ${NAMES[$i]} "echo ${HOSTS[$j]}  ${NAMES[$j]} >> /etc/hosts"
		done
	fi
done

#安装必要软件
for i in "${!HOSTS[@]}"; do
	ssh ${NAMES[$i]} "yum install -y epel-release  net-tools wget vim \
		ntpdate bash-completion lrzsz unzip bridge-utils.x86_64"
done

#初始化前准备
wget https://raw.githubusercontent.com/javac2005/k8s/master/aliyun/pre.sh
wget https://raw.githubusercontent.com/javac2005/k8s/master/aliyun/kube-flannel.yml
chmod +x pre.sh
for i in "${!HOSTS[@]}"; do
	scp pre.sh ${NAMES[$i]}:
	ssh ${NAMES[$i]} ./pre.sh
done

#下载镜像
for imageName in \
	kube-proxy:v1.13.1 \
	kube-apiserver:v1.13.1 \
	kube-controller-manager:v1.13.1 \
	kube-scheduler:v1.13.1 \
	coredns:1.2.6 \
	etcd:3.2.24 \
	pause:3.1; \
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

mkdir -p images

for imageName in $(docker images | awk 'NR!=1{print $1}') ; do
	docker save $imageName  -o "images/${imageName##*/}.tar";
done

for i in "${!HOSTS[@]}"; do
	if [[ ${NAMES[$i]} != ${NAMES[0]} ]]
		then
		scp -r images ${NAMES[$i]}:
		ssh ${NAMES[$i]} 'cd images && for imageName in $(ls); do  docker load < $imageName; done'
	fi
done

#初始化配置文件：kubeadm-config.yaml
cat << EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v1.13.1
apiServer:
  certSANs:
  - ${API_SERVER}
  - ${HOSTS[0]}
  - ${HOSTS[1]}
  - ${HOSTS[2]}
  - ${NAMES[0]}
  - ${NAMES[1]}
  - ${NAMES[2]}
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
controlPlaneEndpoint: ${API_SERVER}:6443
EOF

#初始化master
kubeadm init --config=kubeadm-config.yaml
mkdir -p .kube && rm -rf .kube/config && cp /etc/kubernetes/admin.conf .kube/config
sysctl net.bridge.bridge-nf-call-iptables=1
kubectl apply -f kube-flannel.yml

echo '60秒后开始初始化其他master节点'
sleep 60

#加入其它master - 拷贝证书
for i in "${!NAMES[@]}"; do
	if [[ ${NAMES[$i]} != ${NAMES[0]} ]]
		then
		ssh ${NAMES[$i]} "mkdir -p /etc/kubernetes/pki/etcd"
		scp /etc/kubernetes/pki/ca.crt ${NAMES[$i]}:/etc/kubernetes/pki/
		scp /etc/kubernetes/pki/ca.key ${NAMES[$i]}:/etc/kubernetes/pki/
		scp /etc/kubernetes/pki/sa.key ${NAMES[$i]}:/etc/kubernetes/pki/
		scp /etc/kubernetes/pki/sa.pub ${NAMES[$i]}:/etc/kubernetes/pki/
		scp /etc/kubernetes/pki/front-proxy-ca.crt ${NAMES[$i]}:/etc/kubernetes/pki/
		scp /etc/kubernetes/pki/front-proxy-ca.key ${NAMES[$i]}:/etc/kubernetes/pki/
		scp /etc/kubernetes/pki/etcd/ca.crt ${NAMES[$i]}:/etc/kubernetes/pki/etcd/
		scp /etc/kubernetes/pki/etcd/ca.key ${NAMES[$i]}:/etc/kubernetes/pki/etcd/
		scp /etc/kubernetes/admin.conf ${NAMES[$i]}:/etc/kubernetes/
	fi
done

#加入其它master - 准备token
MASTER_TOKEN=`kubeadm token list | awk 'NR==2{print $1}'`
DISCOVERY_TOKEN=`openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'`

#加入其它master - 初始化、加入
for i in "${!NAMES[@]}"; do
	if [[ ${NAMES[$i]} != ${NAMES[0]} ]]
		then
		ssh ${NAMES[$i]} "kubeadm join ${API_SERVER}:6443 \
		--token ${MASTER_TOKEN} --discovery-token-ca-cert-hash \
		sha256:${DISCOVERY_TOKEN} --experimental-control-plane"
		sleep 5
	fi
done