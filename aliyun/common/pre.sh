#!/bin/bash

echo '############停止并关闭防火墙'
systemctl stop firewalld.service || true
systemctl disable firewalld.service || true

echo '############禁用SELINUX'
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

echo '############设置转发规则'
modprobe bridge
modprobe br_netfilter
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
vm.swappiness=0
EOF

sysctl --system

echo '############禁用虚拟内存'
swapoff -a
sed -i 's/^.*swap*/#&/g' /etc/fstab

echo '############同步时间'
rm -rf /etc/localtime
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
ntpdate -u cn.pool.ntp.org

echo '############设置阿里云源'
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF

echo '############安装并启动docker的17.03.2.ce版'
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache fast
sudo yum install -y --setopt=obsoletes=0 \
    docker-ce-selinux-17.03.2.ce-1.el7.centos \
    docker-ce-17.03.2.ce-1.el7.centos
systemctl enable docker.service
systemctl start docker.service

echo '############安装kubeadm、kubectl、kubelet，1.13.3版本'
yum install -y kubelet-1.13.3 \
    kubeadm-1.13.3 \ 
    kubectl-1.13.3  --disableexcludes=kubernetes
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

#有时候flannel的InitContainer无法正常运行，手动设置：
echo '############设置CNI网络'
mkdir -p /etc/cni/net.d/
cat <<EOF> /etc/cni/net.d/10-flannel.conflist
{
  "name": "cbr0",
  "plugins": [
    {
      "type": "flannel",
      "delegate": {
        "hairpinMode": true,
        "isDefaultGateway": true
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    }
  ]
}
EOF

#echo '############命令补全'
#source /usr/share/bash-completion/bash_completion
#source <(kubectl completion bash)
#echo "source <(kubectl completion bash)" >> ~/.bashrc