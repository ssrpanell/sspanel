#!/bin/bash
#Time: 2018-4-14 10:10:41
#Author: marisn
#Blog: blog.67cc.cn
#更新日志：
#2018-5-13 11:31:59
#增加系统检测，避免错误

#2018-5-7 13:19:52
#修复CyMySQL

#2018-4-14 10:12:57
#1.采用最新官网生产版搭建，避免不必要的错误
#2.优化lnmp的搭建
#3.修复搭建失败
#4.数据库采用端口888访问
[ $(id -u) != "0" ] && { echo "错误: 您必须以root用户运行此脚本"; exit 1; }
function check_system(){
	if [[ -f /etc/redhat-release ]]; then
		release="centos"
	elif cat /etc/issue | grep -q -E -i "debian"; then
		release="debian"
	elif cat /etc/issue | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
	elif cat /proc/version | grep -q -E -i "debian"; then
		release="debian"
	elif cat /proc/version | grep -q -E -i "ubuntu"; then
		release="ubuntu"
	elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
		release="centos"
    fi
	bit=`uname -m`
	if [[ ${release} = "centos" ]] && [[ ${bit} == "x86_64" ]]; then
	echo -e "你的系统为[${release} ${bit}],检测\033[32m 可以 \033[0m搭建。"
	else 
	echo -e "你的系统为[${release} ${bit}],检测\033[31m 不可以 \033[0m搭建。"
	echo -e "\033[31m 正在退出脚本... \033[0m"
	exit 0;
	fi
}
function install_ssrpanel(){
	yum -y remove httpd
	yum install -y unzip zip git
	#自动选择下载节点
	GIT='raw.githubusercontent.com'
	MY='gitee.com'
	GIT_PING=`ping -c 1 -w 1 $GIT|grep time=|awk '{print $7}'|sed "s/time=//"`
	MY_PING=`ping -c 1 -w 1 $MY|grep time=|awk '{print $7}'|sed "s/time=//"`
	echo "$GIT_PING $GIT" > ping.pl
	echo "$MY_PING $MY" >> ping.pl
	fileinfo=`sort -V ping.pl|sed -n '1p'|awk '{print $2}'`
	if [ "$fileinfo" == "$GIT" ];then
		fileinfo='https://raw.githubusercontent.com/marisn2017/ssrpanel/master/fileinfo.zip'
	else
		fileinfo='https://gitee.com/marisn/ssrpanel_one_key/raw/master/fileinfo.zip'
	fi
	rm -f ping.pl	
	 wget -c --no-check-certificate https://raw.githubusercontent.com/marisn2017/ssrpanel/master/lnmp1.4.zip && unzip lnmp1.4.zip && rm -rf lnmp1.4.zip && cd lnmp1.4 && chmod +x install.sh && ./install.sh
	clear
	#安装fileinfo必须组件
	cd /root && wget --no-check-certificate $fileinfo
	File="/root/fileinfo.zip"
    if [ ! -f "$File" ]; then  
    echo "fileinfo组件下载失败，请检查/root/fileinfo.zip"
	exit 0;
	else
    unzip fileinfo.zip
    fi
	cd /root/fileinfo && /usr/local/php/bin/phpize && ./configure --with-php-config=/usr/local/php/bin/php-config --with-fileinfo && make && make install
	cd /home/wwwroot/
	cp -r default/phpmyadmin/ .  #复制数据库
	cd default
	rm -rf index.html
	#获取git最新released版文件 适用于生产环境
	ssrpanel_new_ver=$(wget --no-check-certificate -qO- https://api.github.com/repos/ssrpanel/SSRPanel/releases | grep -o '"tag_name": ".*"' |head -n 1| sed 's/"//g;s/v//g' | sed 's/tag_name: //g')
	wget -c --no-check-certificate "https://github.com/ssrpanel/SSRPanel/archive/${ssrpanel_new_ver}.tar.gz"
	tar zxvf "${ssrpanel_new_ver}.tar.gz" && cd SSRPanel-* && mv * .[^.]* ..&& cd /home/wwwroot/default && rm -rf "${ssrpanel_new_ver}.tar.gz"
	#替换数据库配置
	wget -N -P /home/wwwroot/default/config/ https://raw.githubusercontent.com/marisn2017/ssrpanel/master/app.php
	wget -N -P /home/wwwroot/default/config/ https://raw.githubusercontent.com/marisn2017/ssrpanel/master/database.php
	wget -N -P /usr/local/php/etc/ https://raw.githubusercontent.com/marisn2017/ssrpanel/master/php.ini
	wget -N -P /usr/local/nginx/conf/ https://raw.githubusercontent.com/marisn2017/ssrpanel/master/nginx.conf
	service nginx restart
	#设置数据库
	#mysql -uroot -proot -e"create database ssrpanel;" 
	#mysql -uroot -proot -e"use ssrpanel;" 
	#mysql -uroot -proot ssrpanel < /home/wwwroot/default/sql/db.sql
	#开启数据库远程访问，以便对接节点
	#mysql -uroot -proot -e"use mysql;"
	#mysql -uroot -proot -e"GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'root' WITH GRANT OPTION;"
	#mysql -uroot -proot -e"flush privileges;"
mysql -hlocalhost -uroot -proot --default-character-set=utf8mb4<<EOF
create database ssrpanel;
use ssrpanel;
source /home/wwwroot/default/sql/db.sql;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY 'root' WITH GRANT OPTION;
flush privileges;
EOF
	#安装依赖
	cd /home/wwwroot/default/
	php composer.phar install
	php artisan key:generate
    chown -R www:www storage/
    chmod -R 777 storage/
	chattr -i .user.ini
	mv .user.ini public
	chown -R root:root *
	chmod -R 777 *
	chown -R www:www storage
	chattr +i public/.user.ini
	service nginx restart
    service php-fpm restart
	#开启日志监控
	yum -y install vixie-cron crontabs
	rm -rf /var/spool/cron/root
	echo '* * * * * php /home/wwwroot/default/artisan schedule:run >> /dev/null 2>&1' >> /var/spool/cron/root
	service crond restart
	#修复数据库
	# mv /home/wwwroot/default/phpmyadmin/ /home/wwwroot/default/public/
	# cd /home/wwwroot/default/public/phpmyadmin
	# chmod -R 755 *
	lnmp restart
	IPAddress=`wget http://members.3322.org/dyndns/getip -O - -q ; echo`;
	echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
	echo "#    一键搭建前端面板完成，请访问http://${IPAddress}~ 查看         #"
	echo "#         Author: marisn          Ssrpanel:ssrpanel                #"
	echo "#         Blog: http://blog.67cc.cn/                               #"
	echo "#         Github: https://github.com/marisn2017/ssrpanel           #"
	echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
}
function install_log(){
    myFile="/root/shadowsocksr/ssserver.log"  
	if [ ! -f "$myFile" ]; then  
    echo "您的shadowsocksr环境未安装"
	echo "请检查/root/shadowsocksr/ssserver.log是否存在"
	else
	cd /home/wwwroot/default/storage/app/public
	ln -S ssserver.log /root/shadowsocksr/ssserver.log
	chown www:www ssserver.log
	chmod 0777 /home/wwwroot/default/storage/app/public/ssserver.log
	chmod 777 -R /home/wwwroot/default/storage/logs/
	echo "日志分析（仅支持单机单节点） - 安装成功"
    fi
}
function change_password(){
	echo -e "\033[31m注意:必须正确填写数据库密码，否则只能手动修改。\033[0m"
	read -p "请输入数据库密码(初始密码为root):" Default_password
	Default_password=${Default_password:-"root"}
	read -p "请输入要设置的数据库密码:" Change_password
	Change_password=${Change_password:-"root"}
	echo -e "\033[31m您设置的密码是:${Change_password}\033[0m"
mysql -hlocalhost -uroot -p$Default_password --default-character-set=utf8<<EOF
use mysql;
update user set password=passworD("${Change_password}") where user='root';
flush privileges;
EOF
	echo "开始在设置文件中替换数据库信息..."
	myFile="/root/shadowsocksr/server.py"
    if [ ! -f "$myFile" ]; then  
    sed -i "s/'password' => '"${Default_password}"'/'password' => '"${Change_password}"'/g" /home/wwwroot/default/config/database.php
	echo "数据库密码已完成，请记住。."
	echo "您设置的密码是:${Change_password}"
	else
	sed -i 's/"password": "'${Default_password}'",/"password": "'${Change_password}'",/g' /root/shadowsocksr/usermysql.json
	sed -i "s/'password' => '"${Default_password}"'/'password' => '"${Change_password}"'/g" /home/wwwroot/default/config/database.php
	echo "重新启动配置以生效..."
	init 6
    fi

}
function install_ssr(){
	yum -y update
	yum -y install git 
	yum -y install python-setuptools && easy_install pip 
	yum -y groupinstall "Development Tools" 
	#512M chicks add 1 g of Swap
	dd if=/dev/zero of=/var/swap bs=1024 count=1048576
	mkswap /var/swap
	chmod 0644 /var/swap
	swapon /var/swap
	echo '/var/swap   swap   swap   default 0 0' >> /etc/fstab
	#自动选择下载节点
	GIT='raw.githubusercontent.com'
	LIB='download.libsodium.org'
	GIT_PING=`ping -c 1 -w 1 $GIT|grep time=|awk '{print $7}'|sed "s/time=//"`
	LIB_PING=`ping -c 1 -w 1 $LIB|grep time=|awk '{print $7}'|sed "s/time=//"`
	echo "$GIT_PING $GIT" > ping.pl
	echo "$LIB_PING $LIB" >> ping.pl
	libAddr=`sort -V ping.pl|sed -n '1p'|awk '{print $2}'`
	if [ "$libAddr" == "$GIT" ];then
		libAddr='https://raw.githubusercontent.com/echo-marisn/ssrv3-one-click-script/master/libsodium-1.0.13.tar.gz'
	else
		libAddr='https://download.libsodium.org/libsodium/releases/libsodium-1.0.13.tar.gz'
	fi
	rm -f ping.pl
	wget --no-check-certificate $libAddr
	tar xf libsodium-1.0.13.tar.gz && cd libsodium-1.0.13
	./configure && make -j2 && make install
	echo /usr/local/lib > /etc/ld.so.conf.d/usr_local_lib.conf
	ldconfig
	yum -y install python-setuptools
	easy_install supervisor
    cd /root
	wget https://raw.githubusercontent.com/marisn2017/ssrpanel/master/shadowsocksr.zip
	unzip shadowsocksr.zip
	cd shadowsocksr
	./initcfg.sh
	chmod 777 *
	wget -N -P /root/shadowsocksr/ https://raw.githubusercontent.com/marisn2017/ssrpanel/master/user-config.json
	wget -N -P /root/shadowsocksr/ https://raw.githubusercontent.com/marisn2017/ssrpanel/master/userapiconfig.py
	wget -N -P /root/shadowsocksr/ https://raw.githubusercontent.com/marisn2017/ssrpanel/master/usermysql.json
	sed -i "s#Userip#${Userip}#" /root/shadowsocksr/usermysql.json
	sed -i "s#Dbuser#${Dbuser}#" /root/shadowsocksr/usermysql.json
	sed -i "s#Dbport#${Dbport}#" /root/shadowsocksr/usermysql.json
	sed -i "s#Dbpassword#${Dbpassword}#" /root/shadowsocksr/usermysql.json
	sed -i "s#Dbname#${Dbname}#" /root/shadowsocksr/usermysql.json
	sed -i "s#UserNODE_ID#${UserNODE_ID}#" /root/shadowsocksr/usermysql.json
	yum -y install lsof lrzsz python-devel libffi-devel openssl-devel iptables
	systemctl stop firewalld.service
	systemctl disable firewalld.service
}
function install_node(){
	clear
	echo
    echo -e "\033[31m Add a node...\033[0m"
	echo
	sed -i '$a * hard nofile 512000\n* soft nofile 512000' /etc/security/limits.conf
	[ $(id -u) != "0" ] && { echo "错误: 您必须以root用户运行此脚本"; exit 1; }
	echo -e "如果你不知道，你可以直接回车。"
	echo -e "如果连接失败，请检查数据库远程访问是否打开。"
	read -p "请输入您的对接数据库IP(回车默认为本地IP地址):" Userip
	read -p "请输入数据库名称(回车默认为ssrpanel):" Dbname
	read -p "请输入数据库端口(回车默认为3306):" Dbport
	read -p "请输入数据库帐户(回车默认为root):" Dbuser
	read -p "请输入数据库密码(回车默认为root):" Dbpassword
	read -p "请输入您的节点编号(回车默认为1):  " UserNODE_ID
	IPAddress=`wget http://members.3322.org/dyndns/getip -O - -q ; echo`;
	Userip=${Userip:-"${IPAddress}"}
	Dbname=${Dbname:-"ssrpanel"}
	Dbport=${Dbport:-"3306"}
	Dbuser=${Dbuser:-"root"}
	Dbpassword=${Dbpassword:-"root"}
	UserNODE_ID=${UserNODE_ID:-"1"}
	install_ssr
    # 启用supervisord
	echo_supervisord_conf > /etc/supervisord.conf
	sed -i '$a [program:ssr]\ncommand = python /root/shadowsocksr/server.py\nuser = root\nautostart = true\nautorestart = true' /etc/supervisord.conf
	supervisord
	#iptables
	iptables -F
	iptables -X  
	iptables -I INPUT -p tcp -m tcp --dport 22:65535 -j ACCEPT
	iptables -I INPUT -p udp -m udp --dport 22:65535 -j ACCEPT
	iptables-save >/etc/sysconfig/iptables
	iptables-save >/etc/sysconfig/iptables
	echo 'iptables-restore /etc/sysconfig/iptables' >> /etc/rc.local
	echo "/usr/bin/supervisord -c /etc/supervisord.conf" >> /etc/rc.local
	chmod +x /etc/rc.d/rc.local
	touch /root/shadowsocksr/ssserver.log
	chmod 0777 /root/shadowsocksr/ssserver.log
	cd /home/wwwroot/default/storage/app/public/
	ln -S ssserver.log /root/shadowsocksr/ssserver.log
    chown www:www ssserver.log
	chmod 777 -R /home/wwwroot/default/storage/logs/
	clear
	echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
	echo "#                    成功添加节点请登录到前端站点查看              #"
	echo "#                     正在重新启动系统使节点生效……                 #"
	echo "#              Author: marisn          Ssrpanel:ssrpanel           #"
	echo "#              Blog: http://blog.67cc.cn/                          #"
	echo "#              Github: https://github.com/marisn2017/ssrpanel      #"
	echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
	reboot
}
function install_BBR(){
     wget --no-check-certificate https://github.com/teddysun/across/raw/master/bbr.sh&&chmod +x bbr.sh&&./bbr.sh
}
function install_RS(){
     wget -N --no-check-certificate https://github.com/91yun/serverspeeder/raw/master/serverspeeder.sh && bash serverspeeder.sh
}
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
ulimit -c 0
rm -rf ssrpanel*
clear
check_system
sleep 2
echo "#############################################################################"
echo "#                      欢迎使用一键安装ssrpanel和节点脚本。                 #"
echo "#请选择您想要搭建的脚本:                                                    #"
echo "#1.  一键安装ssrpanel前端面板(不包括节点)                                   #"
echo "#2.  一键安装ssrpanel节点(可单独搭建)                                       #"
echo "#3.  一键搭建BBR加速                                                        #"
echo "#4.  一键搭建锐速加速                                                       #"
echo "#5.  ssrpanel官方升级脚本(可能没什么luan用)                                 #"
echo "#6.  日志分析（仅支持单机单节点）                                           #" 
echo "#7.  一键更改数据库密码(仅适用于已搭建前端)                                 #" 
echo "#                                PS:建议请先搭建加速再搭建ssrpanel相关。    #"
echo "#                                     此脚本仅适用于Centos 7. X 64位 系统   #"
echo "#############################################################################"
echo
read num
if [[ $num == "1" ]]
then
install_ssrpanel
elif [[ $num == "2" ]]
then
install_node
elif [[ $num == "3" ]]
then
install_BBR
elif [[ $num == "4" ]]
then
install_RS
elif [[ $num == "5" ]]
then
cd /home/wwwroot/default/
chmod a+x update.sh && sh update.sh
elif [[ $num == "6" ]]
then
install_log
elif [[ $num == "7" ]]
then
change_password
else 
echo '输入错误';
exit 0;
fi;