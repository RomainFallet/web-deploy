#!/bin/bash

# Exit script on error
set -e

### Set up variables for JS/React/Angular app configuration

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

### Set up the web server for JS/React/Angular app

# Create the app directory
sudo mkdir "/var/www/${appname}"

# Set ownership to Apache
sudo chown www-data:www-data "/var/www/${appname}"

# Create an Apache conf file for the app
echo "<VirtualHost ${appdomain}:80>
  # Set up server name
  ServerName ${appdomain}

  # Set up document root
  DocumentRoot /var/www/${appname}
</VirtualHost>" | sudo tee "/etc/apache2/sites-available/${appname}.conf" > /dev/null

# Activate Apache conf
sudo a2ensite "${appname}.conf"

# Restart Apache to make changes available
sudo service apache2 restart

# Get a new HTTPS certficate
sudo certbot certonly --webroot -w "/var/www/${appname}" -d "${appdomain}" -m "${email}" -n --agree-tos

# Replace existing conf
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

    # Set up React/Angular specific configuration
    <Directory />
        Require all denied
    </Directory>
    <Directory /var/www/${appname}>
        Require all granted
        Options -MultiViews
        RewriteEngine on
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteRule ^ index.html [QSA,L]
    </Directory>

    # Configure separate log files
    ErrorLog /var/log/apache2/${appname}.error.log
    CustomLog /var/log/apache2/${appname}.access.log combined

    # Configure HTTPS
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${appdomain}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${appdomain}/privkey.pem
</VirtualHost>" | sudo tee "/etc/apache2/sites-available/${appname}.conf" > /dev/null

# Restart Apache to make changes available
sudo service apache2 restart

### Suite

# Get and execute script directly
appname=${appname} bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy-ubuntu/master/ubuntu18.04_deploy_any_app_suite.sh)"
