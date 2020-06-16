#!/bin/bash

# Exit script on error
set -e

### Set up variables for NodeJS/NestJS app configuration

# Ask email if not already set
if [[ -z "${email}" ]]; then
    read -r -p "Enter your email (needed to set up email monitoring): " email
fi

# Ask app name if not already set
if [[ -z "${appname}" ]]; then
    read -r -p "Enter the name of your app without hyphens (eg. myawesomeapp): " appname
fi

# Ask domain name if not already set
if [[ -z "${appdomain}" ]]; then
    read -r -p "Enter the domain name on which you want your app to be served (eg. example.com or test.example.com): " appdomain
fi

# Ask localport if not already set
if [[ -z "${localport}" ]]; then
    read -r -p "Enter the running local port on which you want requests to be proxied (eg. 3000): " localport
fi

# Ask database password
if [[ -z "${mysqlpassword}" ]]; then
    read -r -p "Enter the database password you want for your app (save it in a safe place): " mysqlpassword
fi

### Set up the web server for NodeJS/NestJS app

# Create the app directory
sudo mkdir -p "/var/www/${appname}"

# Set ownership to Apache
sudo chown www-data:www-data "/var/www/${appname}"

# Activate default conf
sudo a2ensite 000-default.conf

# Restart Apache to make changes available
sudo service apache2 restart

# Get a new HTTPS certficate
sudo certbot certonly --webroot -w "/var/www/html" -d "${appdomain}" -m "${email}" -n --agree-tos

# Disable letsencrypt-webroot conf
sudo a2dissite 000-default.conf

# Create app conf
echo "<VirtualHost ${appdomain}:80>
    # All we need to do here is redirect to HTTPS
    RewriteEngine on
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>

<VirtualHost ${appdomain}:443>
    # Set up server name
    ServerName ${appdomain}

    # Set up server admin email
    ServerAdmin ${email}

    # Set up document root
    DocumentRoot /var/www/${appname}

    # Set up NodeJS/NestJS specific configuration
    <Directory />
        Require all denied
    </Directory>
    Header set Access-Control-Allow-Origin '*'
    ProxyPass / http://localhost:${localport}/

    # Configure separate log files
    ErrorLog /var/log/apache2/${appname}.error.log
    CustomLog /var/log/apache2/${appname}.access.log combined

    # Configure HTTPS
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${appdomain}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${appdomain}/privkey.pem
</VirtualHost>" | sudo tee "/etc/apache2/sites-available/${appname}.conf" > /dev/null

# Activate app conf
sudo a2ensite "${appname}.conf"

# Restart Apache to make changes available
sudo service apache2 restart

### Set up the database

# Create database and related user for the app and grant permissions
sudo mysql -e "CREATE DATABASE ${appname};
CREATE USER ${appname}@localhost IDENTIFIED BY '${mysqlpassword}';
GRANT ALL ON ${appname}.* TO ${appname}@localhost;"

### Suite

# Get and execute script directly
appname=${appname} bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy/master/ubuntu18.04_deploy_any_app_suite.sh)"
