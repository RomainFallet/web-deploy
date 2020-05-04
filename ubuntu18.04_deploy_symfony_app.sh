#!/bin/bash

### Set up variables for PHP/Symfony app deployment

# Ask email if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${email}" ]]; then
    read -r -p "Enter your email (needed to set up email monitoring): " email || exit 1
fi

# Ask app name if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${appname}" ]]; then
    read -r -p "Enter the name of your app without hyphens (eg. myawesomeapp): " appname || exit 1
fi

# Ask domain name if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${appdomain}" ]]; then
    read -r -p "Enter the domain name on which you want your app to be served (eg. example.com or test.example.com): " appdomain || exit 1
fi

# Ask repository URL if not already set (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${apprepositoryurl}" ]]; then
    read -r -p "Enter the Git repository URL of your app: " apprepositoryurl || exit 1
fi

# Ask SSH password if not already set (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${sshpassword}" ]]; then
    read -r -p "Enter a new password for the SSH account that will be created for your app: " sshpassword
fi

### Clone the app

# Clone app repository
sudo git clone "${apprepositoryurl}" "/var/www/${appname}" || exit 1

# Go inside the app directory
cd "/var/www/${appname}" || exit 1

### Set up the database and the production mode

# Generate a random password for the new mysql user
mysqlpassword=$(openssl rand -hex 15) || exit 1

# Create database and related user for the app and grant permissions
sudo mysql -e "CREATE DATABASE ${appname}; || exit 1
CREATE USER ${appname}@localhost IDENTIFIED BY '${mysqlpassword}'; || exit 1
GRANT ALL ON ${appname}.* TO ${appname}@localhost;" || exit 1

# Create .env.local file
sudo cp ./.env ./.env.local || exit 1

# Set APP_ENV to "prod"
sudo sed -i'.tmp' -e 's/APP_ENV=dev/APP_ENV=prod/g' ./.env.local || exit 1

# Set mysql credentials
sudo sed -i'.tmp' -e 's,DATABASE_URL=mysql://db_user:db_password@127.0.0.1:3306/db_name,DATABASE_URL=mysql://'"${appname}"':'"${mysqlpassword}"'@127.0.0.1:3306/'"${appname}"',g' ./.env.local || exit 1

# Remove temporary file
sudo rm ./.env.local.tmp || exit 1

### Set permissions

# Set ownership to Apache
sudo chown -R www-data:www-data "/var/www/${appname}" || exit 1

# Set files permissions to 664
sudo find "/var/www/${appname}" -type f -exec chmod 664 {} \; || exit 1

# Set folders permissions to 775
sudo find "/var/www/${appname}" -type d -exec chmod 775 {} \; || exit 1

### Set up the web server

# Create an Apache conf file for the app
echo "<VirtualHost ${appdomain}:80>
  # Set up server name
  ServerName ${appdomain}

  # Set up document root
  DocumentRoot /var/www/${appname}/public
</VirtualHost>" | sudo tee "/etc/apache2/sites-available/${appname}.conf" > /dev/null || exit 1

# Activate Apache conf
sudo a2ensite "${appname}.conf" || exit 1

# Restart Apache to make changes available
sudo service apache2 restart || exit 1

### Enabling HTTPS & configure for Symfony

# Get a new HTTPS certficate
sudo certbot certonly --webroot -w "/var/www/${appname}/public" -d "${appdomain}" -m "${email}" -n --agree-tos || exit 1

# Check certificates renewal every month
echo '#!/bin/bash
certbot renew' | sudo tee /etc/cron.monthly/certbot-renew.sh > /dev/null || exit 1
sudo chmod +x /etc/cron.monthly/certbot-renew.sh || exit 1

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
</VirtualHost>" | sudo tee "/etc/apache2/sites-available/${appname}.conf" > /dev/null || exit 1

# Restart Apache to make changes available
sudo service apache2 restart || exit 1

### Create a new SSH user for the app

# Encrypt the password
sshencryptedpassword=$(echo "${sshpassword}" | openssl passwd -crypt -stdin) || exit 1

# Create the user and set the default shell
sudo useradd -m -p "${sshencryptedpassword}" -s /bin/bash "${appname}" || exit 1

# Give ownership to the user
sudo chown -R "${appname}:www-data" "/var/www/${appname}" || exit 1

### Create a chroot jail for this user

# Create the jail
sudo username="${appname}" use_basic_commands=n bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/chroot-jail/master/create.sh)" || exit 1

# Mount the app folder into the jail
sudo mount --bind "/var/www/${appname}" "/home/jails/${appname}/home/${appname}" || exit 1

# Make the mount permanent
echo "/var/www/${appname} /home/jails/${appname}/home/${appname} ext4 rw,relatime,data=ordered 0 0" | sudo tee -a /etc/fstab > /dev/null || exit 1

# Clear history for security reasons
unset HISTFILE || exit 1
history -c || exit 1

### Init or update the app

# Go inside the app directory
cd "/var/www/${appname}" || exit 1

# Get latest updates
sudo su "${appname}" -c "git pull" || exit 1

# Install PHP dependencies
sudo su "${appname}" -c "composer install" || exit 1

# Install JS dependencies if package.json is found
sudo su "${appname}" -c "bash -c \"if [[ -f './package.json' ]]; then yarn install; fi\"" || exit 1

# Build assets if build script is found
sudo su "${appname}" -c "bash -c \"if [[ -f './package.json' ]]; then if grep '\"build\":' ./package.json; then yarn build; fi fi\"" || exit 1

# Execute database migrations
sudo su "${appname}" -c "php bin/console doctrine:migrations:diff"
sudo su "${appname}" -c "php bin/console doctrine:migrations:migrate -n"
