#!/bin/bash

# Exit script on error
set -e

### Set up variables for PHP/Symfony app deployment

# Ask email if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${email}" ]]; then
    read -r -p "Enter your email (needed to set up email monitoring): " email
fi

# Ask app name if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${appname}" ]]; then
    read -r -p "Enter the name of your app without hyphens (eg. myawesomeapp): " appname
fi

# Ask domain name if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${appdomain}" ]]; then
    read -r -p "Enter the domain name on which you want your app to be served (eg. example.com or test.example.com): " appdomain
fi

# Ask database password (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${mysqlpassword}" ]]; then
    read -r -p "Enter the database password you want for your app (save it in a safe place): " mysqlpassword
fi

### Set up the web server

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

# Replace existing conf
echo "<VirtualHost *:80>
    # Set up server name
    ServerName ${appdomain}

    # All we need to do here is redirect to HTTPS
    RewriteEngine on
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>

<VirtualHost *:443>
    # Set up server name
    ServerName ${appdomain}

    # Set up server admin email
    ServerAdmin ${email}

    # Set up document root
    DocumentRoot /var/www/${appname}/public
    DirectoryIndex /index.php

    # Set up Symfony specific configuration
    <Directory />
        Require all denied
    </Directory>
    <Directory /var/www/${appname}/public>
        Require all granted
        php_admin_value open_basedir '/var/www/${appname}'
        FallbackResource /index.php
    </Directory>
    <Directory /var/www/${appname}/public/bundles>
        FallbackResource disabled
    </Directory>

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
