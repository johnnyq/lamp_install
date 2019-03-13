#!/bin/bash
#This script installs a lamp environment on ubuntu 18.04 using php-fpm and mariadb
#Enables http2 for faster websites
#Generates a TLS CERT
#Sets some standard security best practices
#Version - Johnny 0.2 2018-07-13

#Variables to use

email=johnny@pittpc.com
domain=$(hostname -f)
timezone=America/New_York
dev=n
le=y
install_nc=n
install_wp=n

#Set Timezone

timedatectl set-timezone $timezone

#Run Updates

apt update
apt dist-upgrade -y

#Install Apache, PHP-FPM, PHP Extensions, MariaDB, and LetsEncrypt Certbot 
apt install apache2 -y
apt install php7.2-fpm -y
apt install python-certbot-apache -y
apt install mariadb-server mariadb-client -y
apt install php7.2-mysql php7.2-curl php7.2-gd php7.2-intl php-pear php-imagick php7.2-imap php-memcache  php7.2-pspell php7.2-recode php7.2-sqlite3 php7.2-tidy php7.2-xmlrpc php7.2-xsl php7.2-mbstring php-gettext php7.2-zip php-apcu -y

#Enable Apache and PHP Mods

a2enmod proxy_fcgi setenvif
a2enconf php7.2-fpm
a2dismod php7.2
a2dismod mpm_prefork
a2enmod mpm_event
echo "Protocols h2 h2c" >> /etc/apache2/apache2.conf
a2enmod http2

#Create Apache virtualhost

echo "
<VirtualHost *:80>
    DocumentRoot /var/www/$domain
    ServerName $domain
    CustomLog /var/log/apache2/$domain-access.log combined
	ErrorLog /var/log/apache2/$domain-error.log
	<Directory /var/www/$domain>
		Options Indexes FollowSymLinks MultiViews
		AllowOverride All
		Require all granted
    </Directory>
</VirtualHost>
" > /etc/apache2/sites-available/$domain.conf

#Disable default apache host and enable new one

a2dissite 000-default
a2ensite $domain

#Turn off Apache info for security

sed -i '/ServerTokens OS/c\ServerTokens Prod' /etc/apache2/conf-available/security.conf
sed -i '/ServerSignature On/c\ServerSignature Off' /etc/apache2/conf-available/security.conf

#Remove default Apache virtual hosts

rm /etc/apache2/sites-available/000-default.conf
rm /etc/apache2/sites-available/default-ssl.conf

#Remove default Apache virtualhost directory
rm -rf /var/www/html

#Make new Apache Host directory and create a few files and set the right permissions

mkdir /var/www/$domain
echo Welcome to $domain > /var/www/$domain/index.html
chown -R www-data:www-data /var/www/$domain

#Create robots.txt file so no search engine indexes our host for security

echo "User-agent: *
Disallow: /" > /var/www/$domain/robots.txt

#Restart Apache so changes can take a effect

service apache2 restart

#Generate LetsEncrypt SSL Cert and auto redirect http request to https

if [ $le = y ] 
then

certbot --apache -d $domain -m $email --agree-tos --redirect --no-eff-email

fi

#Generate random root mysql password and do what mysql_secure_installation does and enable mysql root login 

PASSWORD=$(date +%s|sha256sum|base64|head -c 32)

mysql --user=root <<_EOF_
  UPDATE mysql.user SET Password=PASSWORD('${PASSWORD}') WHERE User='root';
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  UPDATE mysql.user SET plugin='mysql_native_password' WHERE User='root';
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  FLUSH PRIVILEGES;
_EOF_

echo Your MySQL root password is $PASSWORD
echo $PASSWORD > /root/DELETE_ME_MySQL_Root_Password.txt

if [ $dev = y ] 
then

##Development Mode

#Turn on PHP errors so they are viewable from the browser

sed -i '/display_errors = Off/c\display_errors = On' /etc/php/7.2/fpm/php.ini

#Permit SSH remote root login 

echo PermitRootLogin yes >> /etc/ssh/sshd_config
service sshd reload

#Create php info file to display system dev information 
echo "<?php phpinfo(); ?>" > /var/www/$domain/info.php

#Install Latest PhpMyadmin

wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-english.tar.gz
tar -xzf phpMyAdmin-latest-english.tar.gz -C /var/www/$domain
rm phpMyAdmin-latest-english.tar.gz
mv /var/www/$domain/phpMyAdmin-* /var/www/$domain/phpmyadmin

fi

#Install Wordpress

if [ $install_wp = y ] 
then

wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz -C /var/www/$domain
rm latest.tar.gz

fi

#Install Nextcloud

if [ $install_nc = y ]
then

wget https://download.nextcloud.com/server/releases/latest.tar.bz2
tar -jxf latest.tar.bz2 -C /var/www/$domain
rm latest.tar.bz2

mysql -u root -p$PASSWORD -e "CREATE DATABASE nextcloud"

echo "
<?php
\$AUTOCONFIG = array(
  \"dbtype\"        => \"mysql\",
  \"dbname\"        => \"nextcloud\",
  \"dbuser\"        => \"root\",
  \"dbpass\" 		=> \"$PASSWORD\",
  \"dbhost\"        => \"localhost\",
  \"dbtableprefix\" => \"\",
  \"adminlogin\"    => \"root\",
  \"adminpass\" 	=> \"$PASSWORD\",
  \"memcache.local\" => \"\\OC\\Memcache\\APCu\",
  \"directory\" 	=> \"/var/www/$domain/nextcloud/data\",
);" > /var/www/$domain/nextcloud/config/autoconfig.php

echo "
#Nextcloud OP Cache Settings
opcache.enable=1
opcache.enable_cli=1
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.memory_consumption=128
opcache.save_comments=1
opcache.revalidate_freq=1
" >> /etc/php/7.2/fpm/php.ini

chown -R www-data:www-data /var/www

fi