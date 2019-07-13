#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#=================================================================#
#   System Required: CentOS 7 X86_64                              #
#   Description: Caddy + v2Ray + TLS + WebSocket Soft Install     #
#   Author: LALA <QQ1062951199>                                   #
#   Website: https://www.lala.im                                  #
#=================================================================#

# 颜色选择
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
font="\033[0m"

v2ray_install(){

	# 变量
	read -p "输入你的域名 (不要带http://):" Domain
	read -p "输入你的邮箱 (用于自动签发SSL证书):" Email
	read -p "输入Caddy监听端口 (建议443):" Port

	# 关闭SELinux
	if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
		sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
		setenforce 0
	fi

	# 关闭防火墙
	systemctl disable firewalld.service
	systemctl stop firewalld.service

	# 某些奇葩机器C7可能还带iptables
	systemctl disable iptables.service
	systemctl stop iptables.service

	# 生成UUID
	uuid=$(cat /proc/sys/kernel/random/uuid)

	# 安装Curl
	yum -y install curl

	# 安装V2ray
	bash <(curl -L -s https://install.direct/go.sh)

	# 写入配置文件
	cat > /etc/v2ray/config.json <<EOF
{
  "inbounds": [
    {
      "port": 10000,
      "listen":"127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${uuid}",
            "alterId": 64
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
        "path": "/imlala"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

	# 安装并配置Caddy
	cd ~
	curl https://getcaddy.com | bash -s personal http.filebrowser
	if [ $? -eq 0 ];then
	    echo -e "${green} Caddy安装完成 ${font}"
	else 
	    echo -e "${red} Caddy安装失败 ${font}"
	    exit 1
	fi

	mkdir -p /etc/caddy && mkdir -p /etc/ssl/caddy

	read -p "是否需要把站点伪装成一个网盘?如选择伪装,在安装完成之后请访问${Domain}:${Port}修改管理员账号密码,默认均为:admin(yes/no):" mask
	if [ $mask = "yes" ];then
	cat > /etc/caddy/Caddyfile <<EOF
${Domain}:${Port} {
	log stdout
	tls ${Email}
	filebrowser / /opt
	proxy /imlala localhost:10000 {
		websocket
		header_upstream -Origin
	}
}
EOF
	fi
	if [ $mask = "no" ];then
	cat > /etc/caddy/Caddyfile <<EOF
${Domain}:${Port} {
	log stdout
	tls ${Email}
	proxy /imlala localhost:10000 {
		websocket
		header_upstream -Origin
	}
}
EOF
	fi

	#创建Caddy服务文件
	cat > /etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy HTTP/2 web server
Documentation=https://caddyserver.com/docs
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Restart=on-abnormal
User=root
Group=root
Environment=CADDYPATH=/etc/ssl/caddy
ExecStart=/usr/local/bin/caddy -log stdout -agree=true -conf=/etc/caddy/Caddyfile
ExecReload=/bin/kill -USR1 \$MAINPID
KillMode=mixed
KillSignal=SIGQUIT
TimeoutStopSec=5s

[Install]
WantedBy=multi-user.target
EOF

	#启动Caddy
	systemctl enable caddy
	systemctl start caddy

	#启动v2Ray
	systemctl start v2ray
	systemctl enable v2ray

	# 打印客户端配置信息
	clear
	echo -e "${green} 安装完成 ${font}"
	echo -e "${yellow} 客户端连接地址(Address) : ${Domain} ${font}"
	echo -e "${yellow} 端口(Port) : ${Port} ${font}"
	echo -e "${yellow} 用户ID(UUID) : ${uuid} ${font}"
	echo -e "${yellow} 额外ID(Alterid) : 64 ${font}"
	echo -e "${yellow} 传输协议(Network) : WS ${font}"
	echo -e "${yellow} 路径(Path) : /imlala ${font}"
}

kernelpcc_install(){

	# 更新系统
	yum -y update

	# 安装依赖
	yum -y install kernel-headers-$(uname -r) kernel-devel-$(uname -r)
	yum -y install centos-release-scl
	yum -y groupinstall "Development Tools"
	yum -y install devtoolset-7-gcc*

	# 下载源码
	cd ~
	git clone https://github.com/giltu/KernelPCC.git
	cd KernelPCC

	# 修复编译内核的路径和版本
	cat > Makefile <<EOF
obj-m += tcp_TA.o
KVERSION := /usr/src/kernels/\$(shell uname -r)	
PWD := \$(shell pwd)
default:
	make -C \$(KVERSION) SUBDIRS=\$(PWD) modules
clean:
	make -C \$(KVERSION) M=\$(PWD) clean
EOF

	# 使用高版本GCC编译
	scl enable devtoolset-7 make

	# 加载模块到内核
	insmod tcp_TA.ko

	# 启用模块
	echo "net.ipv4.tcp_congestion_control=TA" >> /etc/sysctl.conf
	sysctl -p

	# 开机启动
	echo "insmod ~/KernelPCC/tcp_TA.ko" >> /etc/rc.d/rc.local
	chmod +x /etc/rc.d/rc.local

	# 清屏打印输出
	clear
	echo -e "${green} 安装完成请执行命令查看是否启用成功: sysctl net.ipv4.tcp_congestion_control ${font}"
	echo -e "${green} 如输出结果=号后面有TA字样则说明成功 ${font}"
}

# 开始菜单设置
echo -e "${yellow} CentOS7 X86_64 Caddy + v2Ray + TLS + WebSocket 一键安装脚本 ${font}"
echo -e "${yellow} Author LALA Website WWW.LALA.IM ${font}"
start_menu(){
	read -p "请输入数字(1或2),1安装v2Ray,2安装KernelPCC(类似BBR的单边加速):" num
	case "$num" in
		1)
		v2ray_install
		;;
		2)
		kernelpcc_install
		;;
	esac
}

# 运行开始菜单
start_menu
