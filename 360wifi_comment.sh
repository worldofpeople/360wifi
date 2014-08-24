#!/bin/bash

# 创建函数，当输入的命令参数不正确，用来输出提示信息
function usage() {
    echo "[x] Usage: `basename $0` [360-wifi-interface] [public-network-interface] [password(optional)] "
    echo "   [360-wifi-interface]: the network interface of 360-wifi, wlan0 for example."
    echo "   [public-network-interface]: the network interface of public network, eth0 for example."
    echo "   [password(optional)]: password of your new WIFI network (>=8 bytes). "
    exit
}

# 检查参数个数
# 如果参数个数小于2 或者 大于3，则执行usage,打印提示信息
# $# 用来获取脚本所带参数数量
# a -lt b  测试整数 a 是否小于 b 
# a -gt b  测试整数 a 是否大于 b
if [ $# -lt 2 ] || [ $# -gt 3 ] ; then
    usage
fi

# 产生随机数密码
key=$(echo $RANDOM)$(echo $RANDOM)

# 如果用户设置了密码，则将密码替换为用户设置的密码
# a -eq b　测试整数 a 与 b 是否相等
if [ $# -eq 3 ]; then
    key=$3
fi

# 如果密码长度小于8，则输出提示信息，并退出。
# #key　计算变量 key 的长度
# exit	退出：成功时，返回0；失败时，返回1。
if [ ${#key} -lt 8 ]; then
    echo "[x] The length of password can not be less than 8."
    exit
fi

# 网络出入口，网络设备别名
# in_interface　 为 360wifi 的设备名
# out_interface  为本地连接的设备名
in_interface=$1
out_interface=$2

# 将存储配置文件的路径赋给变量 WIFI_HOME 
WIFI_HOME=~/.360wifi

# 设置全局变量 LANG 
export LANG='en_US.UTF-8'


#[1] Check whether we have 360 wifi inserted

echo "[*] Checking 360-wifi ... "
# 根据 360wifi 的 ID 搜索其是否在 usb 设备列表中，从而判断其是否已插入
# lsusb，列出 usb 设备
result=$(lsusb | grep -E "148f:5370|148f:760b")

# 特殊变量 $? 保存上个执行命令的退出状态码。0为真，其它为假。
# a -ne b　测试整数 a 与 b 是否不相等
if [ $? -ne 0 ]; then
    echo "[x] Please insert 360-wifi into the USB interface"
    exit
fi

#[2] check whether kernel has CONFIG_RT2800USB_RT53XX configuration
#CONFIG_RT2800USB_RT53XX=y
echo "[*] Checking kernel version ... "

# 获得内核版本
kernel_version=$(uname -r)

# 在配置文件中搜索是否存在 CONFIG_RT2800USB_RT53XX=y 
result=$(cat /boot/config-$kernel_version | grep -e "CONFIG_RT2800USB_RT53XX=y")

if [ $? -ne 0 ]; then
    echo "[x] Sorry, your kernel version is not currently supported"
    exit
fi


# [3] install necessary packages
echo "[*] Installing necessary packages ... "

yum list installed | grep hostapd > /dev/null
if [ $? -ne 0 ]
then
	echo "    -->[a] hostapd is installing ..."
	sudo yum install hostapd > /dev/null
else
	echo "    -->[a] hostapd is already installed."
fi

yum list installed | grep dhcp > /dev/null
if [ $? -ne 0 ]
then
	echo "    -->[b] dhcp is installing ..."
	sudo yum install dhcp > /dev/null
else
	echo "    -->[b] dhcp is already installed."
fi


# [4] set isc-dhcp-server
echo "[*] Setting isc-dhcp-server ... "
# if [ -f FILE] then ... fi 
# -f : True if FILE exits and is a regular file (not a device or a directory)
if [ -f /etc/dhcp/dhcpd.$in_interface.conf ]; then
    sudo rm /etc/dhcp/dhcpd.$in_interface.conf
fi

# 通过 "inet " 排除掉 inet6 。
# awk '{print $2}' 使用默认的空白字符（如空格或制表符作为字段的分隔符）
# awk -F. '{print $1}'` 使用 '.' 作为分隔符
ip_prefix=`ifconfig ${out_interface} | grep "inet " | awk '{print $2}' | awk -F. '{print $1}'`
case ${ip_prefix} in
    "10")
        ip_prefix="172.16"
        ;;
    "172")
        ip_prefix="192.168"
        ;;
    "192")
        ip_prefix="10.0"
        ;;
    "210")
        ip_prefix="10.0"
        ;;
    "")
        echo '!are you sure you have connected to internet'
        ;;
    *)
        ip_prefix="10.0"
        ;;
esac

subnet="${ip_prefix}.9"

# 配置 dhcpd 服务器
# default-lease-time             默认租约时间
# max-lease-time                 最大租约时间
# range                          可用 IP 范围
# option domain-name-servers     设置 DNS 地址
# option routers                 设置路由地址
# tee  /etc/dhcp/dhcpd.$in_interface.conf > /dev/null 
# tee 将输入内容重定向到 /etc/dhcp/dhcpd.$in_interface.conf 和 /dev/null ，
# > /dev/null , 将本来该输出到 STDOUT 的数据流重定向到 /dev/null ,
# 这样，终端就不会显示出入内容
echo "default-lease-time 600;
max-lease-time 7200;
log-facility local7;
subnet ${subnet}.0 netmask 255.255.255.0 {
    range ${subnet}.100 ${subnet}.200;
    option domain-name-servers 8.8.8.8;
    option routers ${subnet}.1;
    default-lease-time 600;
    max-lease-time 7200;
}" | sudo tee  /etc/dhcp/dhcpd.$in_interface.conf > /dev/null

# man ifconfig
sudo ifconfig $in_interface ${subnet}.1 up
# man dhcpd
# 动态配置 DHCP (Dynamic Host Configuration Protocal) ，是一个局域网的网络协议，
# 使用 UDP 协议工作，主要有两个用途：
# 1、给内部网络或网络服务供应商自动分配 IP 地址给用户
# 2、给内部网络管理员作为对所有电脑做中央管理的手段
# -q , Be quiet at startup
# -cf -- config-file, Path to alternate configuration file
# -pf -- pid-file, Path to alternate pid file
sudo dhcpd -q -cf /etc/dhcp/dhcpd.$in_interface.conf -pf /var/run/dhcpd.pid  $in_interface


echo "[*] Setting iptable ... "
# 检查 Linux 的 IP 转发功能是否打开。若没打开，则打开。
forward=$(cat  /proc/sys/net/ipv4/ip_forward)
if [ $forward -eq "0" ]; then
    echo "    -->[*] Enabling ipv4 forwarding"
    echo 1  | sudo tee  /proc/sys/net/ipv4/ip_forward
fi

# 配置 iptables 规则
# man iptables
echo "    -->[*] Setting iptables rules"
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t nat -A POSTROUTING -s ${subnet}.0/24 -o $out_interface -j MASQUERADE
sudo iptables -A FORWARD -s ${subnet}.0/24 -o $out_interface -j ACCEPT
sudo iptables -A FORWARD -d ${subnet}.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -i $out_interface -j ACCEPT

echo "[*] Setting hostapd ... "

#ssid=360_FREE_WIFI$RANDOM
ssid=vision

echo
echo "****  SSID : $ssid, key: $key. Enjoy! ****"
echo
function clean_up {
    echo "[*] Cleaning up ..."
    if [ -f /var/run/dhcp-server/dhcpd.pid ]; then
        dhcpd_pid=$(cat /var/run/dhcp-server/dhcpd.pid)
        sudo kill -9 $dhcpd_pid > /dev/null
        # echo $dhcpd_pid
    fi
}

trap 'clean_up;echo "Goodbye"' SIGINT SIGTERM SIGQUIT SIGKILL

if [ ! -d $WIFI_HOME ]; then
    mkdir $WIFI_HOME
fi

if [ -f $WIFI_HOME/.hostapd.$in_interface.conf ]; then
    rm $WIFI_HOME/.hostapd.$in_interface.conf
fi

# 配置 hostapd
# hostapd ，用于AP(Access Point, 接入点) 和 认证服务器的守护进程
# man hostapd 
# ssid=$ssid                热点名
# wpa_passphrase=$key       密钥 
# wpa_key_mgmt=WPA-PSK      密钥类型
echo "interface=$in_interface
driver=nl80211
ssid=$ssid
hw_mode=g
channel=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=3
wpa_passphrase=$key
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP" | tee  $WIFI_HOME/.hostapd.$in_interface.conf > /dev/null

sudo hostapd $WIFI_HOME/.hostapd.$in_interface.conf
#sudo hostapd $WIFI_HOME/.hostapd.$in_interface.conf  > /dev/null
#sudo hostapd $WIFI_HOME/.hostapd.$in_interface.conf  -P $WIFI_HOME/.hostapd.$in_interface.pid
#sudo hostapd $WIFI_HOME/.hostapd.$in_interface.conf  -P $WIFI_HOME/.hostapd.$in_interface.pid -B

