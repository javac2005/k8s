#!/bin/bash

API_SERVER_DOMAIN=""
API_SERVER_IP=""
MASTER_IPS=""
NODE_IPS=""
ROOT_PASSWORD=""

echo "参数接收"
SHOW_USAGE="-a | --api-server-domain , -b | --api-server-ip , -m | --master-ips , -n | --node-ips , -r | --root-password"
GETOPT_ARGS=`getopt -o a:b:m:n:r: -al api-server-domain:,api-server-ip:,master-ips:,node-ips:,root-password: -- "$@"`
eval set -- "$GETOPT_ARGS"
while [ -n "$1" ]
do
        case "$1" in
                -a|--api-server-domain) API_SERVER_DOMAIN=$2; shift 2;;
                -b|--api-server-ip)     API_SERVER_IP=$2;     shift 2;;
                -m|--master-ips)        MASTER_IPS=$2;        shift 2;;
                -n|--node-ips)          NODE_IPS=$2;          shift 2;;
                -r|--root-password)     ROOT_PASSWORD=$2;     shift 2;;
                --) break ;;
                *)  echo $1,$2,$SHOW_USAGE; break ;;
        esac
done

echo "检查参数"
if [[ -z $API_SERVER_DOMAIN || -z $MASTER_IPS || -z $NODE_IPS || -z $ROOT_PASSWORD ]]; then
    echo "参数错误，必传："$SHOW_USAGE
    exit 0
fi

#定义数组
MASTERS=($MASTER_IPS)
NODES=($NODE_IPS)
MASTER_NAMES=()
NODE_NAMES=()

#如果没有传--api-server-ip参数，默认为第一个master的IP
if [[ -z $API_SERVER_IP ]]; then
	API_SERVER_IP=${MASTERS[0]}
fi

#为master的name数组赋值
for i in "${!MASTERS[@]}"; do
    MASTER_NAMES[$i]=master$i
done
#为node的name数组赋值
for i in "${!NODES[@]}"; do
    NODE_NAMES[$i]=node$i
done

echo "准备环境"
yum -y install expect
wget https://raw.githubusercontent.com/javac2005/k8s/master/cluster/install/common/auto_ssh.sh
wget https://raw.githubusercontent.com/javac2005/k8s/master/cluster/install/common/pre.sh
wget https://raw.githubusercontent.com/javac2005/k8s/master/cluster/install/resources/kube-flannel.yml
chmod +x auto_ssh.sh pre.sh

echo "配置本机hosts"
for i in "${!MASTERS[@]}"; do
    echo "${MASTERS[$i]}  ${MASTER_NAMES[$i]}" >> /etc/hosts
    echo "${NODES[$i]}  ${NODE_NAMES[$i]}" >> /etc/hosts
done

echo "生成密钥，做免密登录"
ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa
for i in "${!MASTERS[@]}"; do
    ./auto_ssh.sh ${ROOT_PASSWORD} ${MASTER_NAMES[$i]}
done
for i in "${!NODES[@]}"; do
    ./auto_ssh.sh ${ROOT_PASSWORD} ${NODE_NAMES[$i]}
done

echo "设置主机名，配置hosts"
for i in "${!MASTERS[@]}"; do
    ssh ${MASTER_NAMES[$i]} "hostnamectl set-hostname ${MASTER_NAMES[$i]}"
    ssh ${MASTER_NAMES[$i]} "echo ${MASTERS[0]}  ${API_SERVER_DOMAIN} >> /etc/hosts"
    if [[ ${MASTER_NAMES[$i]} != ${MASTER_NAMES[0]} ]]
        then
        for j in "${!MASTERS[@]}"; do
        ssh ${MASTER_NAMES[$i]} "echo ${MASTERS[$j]}  ${MASTER_NAMES[$j]} >> /etc/hosts"
        done
    fi
done
for i in "${!NODES[@]}"; do
    ssh ${NODE_NAMES[$i]} "\
    	hostnamectl set-hostname ${NODE_NAMES[$i]} &&\ 
    	echo ${NODES[$i]}  ${NODE_NAMES[$i]} >> /etc/hosts &&\
    	echo ${API_SERVER_IP}  ${API_SERVER_DOMAIN} >> /etc/hosts"
done

echo "安装必要软件"
for i in "${!MASTERS[@]}"; do
    ssh ${MASTER_NAMES[$i]} "\
    	yum install -y nfs-utils epel-release  net-tools wget vim \
        ntpdate bash-completion lrzsz unzip bridge-utils.x86_64"
done
for i in "${!NODES[@]}"; do
    ssh ${NODE_NAMES[$i]} "\
    	yum install -y nfs-utils epel-release  net-tools wget vim \
        ntpdate bash-completion lrzsz unzip bridge-utils.x86_64"
done

echo "初始化前准备"
for i in "${!MASTERS[@]}"; do
    scp pre.sh ${MASTER_NAMES[$i]}:
    ssh ${MASTER_NAMES[$i]} ./pre.sh
done
for i in "${!NODES[@]}"; do
    scp pre.sh ${NODE_NAMES[$i]}:
    ssh ${NODE_NAMES[$i]} ./pre.sh
done

echo "下载镜像"
for imageName in \
    kube-proxy:v1.13.3 \
    kube-apiserver:v1.13.3 \
    kube-controller-manager:v1.13.3 \
    kube-scheduler:v1.13.3 \
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
docker pull registry.cn-beijing.aliyuncs.com/common-registry/kubeadm:1.13.3

echo "导出镜像"
mkdir -p images
for imageName in $(docker images | awk 'NR!=1{print $1}') ; do
    docker save $imageName  -o "images/${imageName##*/}.tar";
done

echo "将镜像拷贝到其他节点"
for i in "${!MASTERS[@]}"; do
    if [[ ${MASTER_NAMES[$i]} != ${MASTER_NAMES[0]} ]]
        then
        scp -r images ${MASTER_NAMES[$i]}:
        ssh ${MASTER_NAMES[$i]} 'cd images && for imageName in $(ls); do  docker load < $imageName; done'
    fi
done
for i in "${!NODES[@]}"; do
	scp -r images ${NODE_NAMES[$i]}:
	ssh ${NODE_NAMES[$i]} 'cd images && for imageName in $(ls); do  docker load < $imageName; done'
done

echo "初始化配置文件：kubeadm-config.yaml"
CERT_SANS=[\"${API_SERVER_DOMAIN}\"
for i in "${!MASTERS[@]}"; do
    CERT_SANS=${CERT_SANS},\"${MASTERS[$i]}\"
done
for i in "${!MASTERS[@]}"; do
    CERT_SANS=${CERT_SANS},\"${MASTER_NAMES[$i]}\"
done

CERT_SANS=${CERT_SANS}]

cat << EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v1.13.3
apiServer:
  certSANs: ${CERT_SANS}
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
controlPlaneEndpoint: ${API_SERVER_DOMAIN}:6443
EOF

echo "修改证书有效期，从1年修改成20年，解决一年后证书到期集群无法运行的问题"
docker run --rm -v /tmp/kubeadm/:/tmp/kubeadm/ \
    registry.cn-beijing.aliyuncs.com/common-registry/kubeadm:1.13.3 \
    sh -c 'cp /kubeadm /tmp/kubeadm/'
mv /usr/bin/kubeadm /usr/bin/kubeadm_backup
mv /tmp/kubeadm/kubeadm /usr/bin/
chmod +x /usr/bin/kubeadm

echo "初始化master"
kubeadm init --config=kubeadm-config.yaml
mkdir -p .kube && rm -rf .kube/config && cp /etc/kubernetes/admin.conf .kube/config
sysctl net.bridge.bridge-nf-call-iptables=1
kubectl apply -f kube-flannel.yml

echo "60秒后开始初始化其他master节点"
sleep 60

echo "加入其它master - 拷贝证书"
for i in "${!MASTER_NAMES[@]}"; do
    if [[ ${MASTER_NAMES[$i]} != ${MASTER_NAMES[0]} ]]
        then
        ssh ${MASTER_NAMES[$i]} "mkdir -p /etc/kubernetes/pki/etcd"
        scp /etc/kubernetes/pki/ca.crt ${MASTER_NAMES[$i]}:/etc/kubernetes/pki/
        scp /etc/kubernetes/pki/ca.key ${MASTER_NAMES[$i]}:/etc/kubernetes/pki/
        scp /etc/kubernetes/pki/sa.key ${MASTER_NAMES[$i]}:/etc/kubernetes/pki/
        scp /etc/kubernetes/pki/sa.pub ${MASTER_NAMES[$i]}:/etc/kubernetes/pki/
        scp /etc/kubernetes/pki/front-proxy-ca.crt ${MASTER_NAMES[$i]}:/etc/kubernetes/pki/
        scp /etc/kubernetes/pki/front-proxy-ca.key ${MASTER_NAMES[$i]}:/etc/kubernetes/pki/
        scp /etc/kubernetes/pki/etcd/ca.crt ${MASTER_NAMES[$i]}:/etc/kubernetes/pki/etcd/
        scp /etc/kubernetes/pki/etcd/ca.key ${MASTER_NAMES[$i]}:/etc/kubernetes/pki/etcd/
        scp /etc/kubernetes/admin.conf ${MASTER_NAMES[$i]}:/etc/kubernetes/
    fi
done

echo "准备token"
MASTER_TOKEN=`kubeadm token list | awk 'NR==2{print $1}'`
DISCOVERY_TOKEN=`openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
openssl rsa -pubin -outform der 2>/dev/null | openssl dgst -sha256 -hex | sed 's/^.* //'`

echo "其他master节点加入集群"
for i in "${!MASTER_NAMES[@]}"; do
    if [[ ${MASTER_NAMES[$i]} != ${MASTER_NAMES[0]} ]]
        then
        ssh ${MASTER_NAMES[$i]} "docker run --rm -v /tmp/kubeadm/:/tmp/kubeadm/ \
            registry.cn-beijing.aliyuncs.com/common-registry/kubeadm:1.13.3 \
            sh -c 'cp /kubeadm /tmp/kubeadm/'"
        ssh ${MASTER_NAMES[$i]} "mv /usr/bin/kubeadm /usr/bin/kubeadm_backup &&\
        	mv /tmp/kubeadm/kubeadm /usr/bin/ &&\
        	chmod +x /usr/bin/kubeadm"
        ssh ${MASTER_NAMES[$i]} "kubeadm join ${API_SERVER_DOMAIN}:6443 \
        	--token ${MASTER_TOKEN} --discovery-token-ca-cert-hash \
        	sha256:${DISCOVERY_TOKEN} --experimental-control-plane"
        sleep 5
    fi
done

echo "node节点加入集群"
for i in "${!NODES[@]}"; do
    ssh ${NODE_NAMES[$i]} "docker run --rm -v /tmp/kubeadm/:/tmp/kubeadm/ \
        registry.cn-beijing.aliyuncs.com/common-registry/kubeadm:1.13.3 \
        sh -c 'cp /kubeadm /tmp/kubeadm/'"
    ssh ${NODE_NAMES[$i]} "\
    	mv /usr/bin/kubeadm /usr/bin/kubeadm_backup &&\
    	mv /tmp/kubeadm/kubeadm /usr/bin/ &&\
    	chmod +x /usr/bin/kubeadm"
    ssh ${NODE_NAMES[$i]} "kubeadm join ${API_SERVER_DOMAIN}:6443 \
    	--token ${MASTER_TOKEN} --discovery-token-ca-cert-hash \
    	sha256:${DISCOVERY_TOKEN}"
done