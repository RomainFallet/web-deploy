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

# Ask database password (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${mysqlpassword}" ]]; then
    read -r -p "Enter the database password you want for your app (save it in a safe place): " mysqlpassword
fi

### Set up the web server

# Create the app directory
sudo mkdir "/var/www/${appname}"

# Set ownership to Apache
sudo chown www-data:www-data "/var/www/${appname}"

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

### Set up the database

# Create database and related user for the app and grant permissions
sudo mysql -e "CREATE DATABASE ${appname};
CREATE USER ${appname}@localhost IDENTIFIED BY '${mysqlpassword}';
GRANT ALL ON ${appname}.* TO ${appname}@localhost;"
```

### Create a new SSH user for the app

[Back to top ↑](#table-of-contents)

This user will be used to access the app.

```bash
# Generate a new password
sshpassword=$(openssl rand -hex 15)

# Encrypt the password
sshencryptedpassword=$(echo "${sshpassword}" | openssl passwd -crypt -stdin)

# Create the user and set the default shell
sudo useradd -m -p "${sshencryptedpassword}" -s /bin/bash "${appname}"

# Give ownership to the user
sudo chown -R "${appname}:www-data" "/var/www/${appname}"

# Make new files inherit from the group ownership (so that Apache can still access them)
sudo chmod g+s "/var/www/${appname}"

# Create SSH folder in the user home
sudo mkdir -p "/home/${appname}/.ssh"

# Copy the authorized_keys file to enable passwordless SSH connections
sudo cp ~/.ssh/authorized_keys "/home/${appname}/.ssh/authorized_keys"

### Create a chroot jail for this user

# Create the jail
sudo username="${appname}" use_basic_commands=n bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/chroot-jail/master/create.sh)"

# Mount the app folder into the jail
sudo mount --bind "/var/www/${appname}" "/home/jails/${appname}/home/${appname}"

# Make the mount permanent
echo "/var/www/${appname} /home/jails/${appname}/home/${appname} ext4 rw,relatime,data=ordered 0 0" | sudo tee -a /etc/fstab > /dev/null
