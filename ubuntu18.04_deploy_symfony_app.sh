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

# Ask repository URL if not already set (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${apprepositoryurl}" ]]; then
    read -r -p "Enter the Git repository URL of your app: " apprepositoryurl
fi

# Ask SSH password if not already set (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${sshpassword}" ]]; then
    read -r -p "Enter a new password for the SSH account that will be created for your app: " sshpassword
fi

### Clone the app

# Clone app repository
sudo git clone "${apprepositoryurl}" "/var/www/${appname}"

# Go inside the app directory
cd "/var/www/${appname}"

### Set up the database and the production mode

# Generate a random password for the new mysql user
mysqlpassword=$(openssl rand -hex 15)

# Create database and related user for the app and grant permissions
sudo mysql -e "CREATE DATABASE ${appname};
CREATE USER ${appname}@localhost IDENTIFIED BY '${mysqlpassword}';
GRANT ALL ON ${appname}.* TO ${appname}@localhost;"

# Create .env.local file
sudo cp ./.env ./.env.local

# Set APP_ENV to "prod"
sudo sed -i'.tmp' -e 's/APP_ENV=dev/APP_ENV=prod/g' ./.env.local

# Set mysql credentials
sudo sed -i'.tmp' -e 's,DATABASE_URL=mysql://db_user:db_password@127.0.0.1:3306/db_name,DATABASE_URL=mysql://'"${appname}"':'"${mysqlpassword}"'@127.0.0.1:3306/'"${appname}"',g' ./.env.local

# Remove temporary file
sudo rm ./.env.local.tmp

### Set permissions

# Set ownership to Apache
sudo chown -R www-data:www-data "/var/www/${appname}"

# Set files permissions to 664
sudo find "/var/www/${appname}" -type f -exec chmod 664 {} \;

# Set folders permissions to 775
sudo find "/var/www/${appname}" -type d -exec chmod 775 {} \;

### Set up the web server

# Create an Apache conf file for the app
echo "<VirtualHost ${appdomain}:80>
  # Set up server name
  ServerName ${appdomain}

  # Set up document root
  DocumentRoot /var/www/${appname}/public
</VirtualHost>" | sudo tee "/etc/apache2/sites-available/${appname}.conf" > /dev/null

# Activate Apache conf
sudo a2ensite "${appname}.conf"

# Restart Apache to make changes available
sudo service apache2 restart

### Enabling HTTPS & configure for Symfony

# Get a new HTTPS certficate
sudo certbot certonly --webroot -w "/var/www/${appname}/public" -d "${appdomain}" -m "${email}" -n --agree-tos

# Check certificates renewal every month
echo '#!/bin/bash
certbot renew' | sudo tee /etc/cron.monthly/certbot-renew.sh > /dev/null
sudo chmod +x /etc/cron.monthly/certbot-renew.sh

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

# Restart Apache to make changes available
sudo service apache2 restart

### Create a new SSH user for the app

# Encrypt the password
sshencryptedpassword=$(echo "${sshpassword}" | openssl passwd -crypt -stdin)

# Create the user and set the default shell
sudo useradd -m -p "${sshencryptedpassword}" -s /bin/bash "${appname}"

# Give ownership to the user
sudo chown -R "${appname}:www-data" "/var/www/${appname}"

# Make new files inherit from the group ownership
sudo chmod g+s "/var/www/${appname}"

### Create a chroot jail for this user

# Create the jail
sudo username="${appname}" use_basic_commands=n bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/chroot-jail/master/create.sh)"

# Mount the app folder into the jail
sudo mount --bind "/var/www/${appname}" "/home/jails/${appname}/home/${appname}"

# Make the mount permanent
echo "/var/www/${appname} /home/jails/${appname}/home/${appname} ext4 rw,relatime,data=ordered 0 0" | sudo tee -a /etc/fstab > /dev/null

# Clear history for security reasons
unset HISTFILE
history -c

### Init or update the app

# Go inside the app directory
cd "/var/www/${appname}"

# Get latest updates
sudo su "${appname}" -c "git pull"

# Install PHP dependencies
sudo su "${appname}" -c "composer install"

# Install JS dependencies if package.json is found
sudo su "${appname}" -c "yarn install"

# Build assets if build script is found
sudo su "${appname}" -c "yarn build"

# Execute database migrations
sudo su "${appname}" -c "php bin/console doctrine:migrations:diff  --allow-empty-diff"
sudo su "${appname}" -c "php bin/console doctrine:migrations:migrate -n"
