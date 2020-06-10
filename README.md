# The web deploy instructions kit

The purpose of this repository is to provide instructions to configure a web deployment environment.

The goal is to provide an opinionated, fully tested environment, that just work.

## Table of contents

- [Important notice](#important-notice)
- [Prerequisites](#prerequisites)
  - [Create a user account with sudo privileges](#create-a-user-account-with-sudo-privileges)
  - [Configure an SSH key](#configure-an-ssh-key)
- [Quickstart](#quickstart)
- [Manual configuration: server setup](#manual-configuration-server-setup)
    1. [Set up variables](#set-up-variables)
    2. [SSH](#ssh)
    3. [Updates](#Updates)
    4. [Postfix](#postfix)
    5. [Apache 2](#apache-2)
    6. [Certbot](#certbot)
    7. [Firewall](#firewall)
    8. [Fail2ban](#fail2ban)
    9. [PHP environment (optional)](#php-environment-optional)
    10. [NodeJS environment (optional)](#nodejs-environment-optional)
- [Manual configuration: configure an HTML/JS/React/Angular app](#manual-configuration-configure-an-htmljsreactangular-app)
    1. [Set up variables for HTML/JS/React/Angular app configuration](#set-up-variables-for-htmljsreactangular-app-configuration)
    2. [Set up the web server for HTML/JS/React/Angular app](#set-up-the-web-server-for-htmljsreactangular-app)
- [Manual configuration: configure a PHP/Symfony app](#manual-configuration-configure-a-phpsymfony-app)
    1. [Set up variables for PHP/Symfony app configuration](#set-up-variables-for-phpsymfony-app-configuration)
    2. [Set up the web server for PHP/Symfony app](#set-up-the-web-server-for-phpsymfony-app)
    3. [Set up the SQL database](#set-up-the-sql-database)
- [Manual configuration: suite (all apps)](#manual-configuration-suite-all-apps)
    1. [Create a new SSH user for the app](#create-a-new-ssh-user-for-the-app)
    2. [Create a chroot jail for this user](#create-a-chroot-jail-for-this-user)
    3. [Transfer your files from your computer](#transfer-your-files-from-your-computer)
    4. [Transfer your files from CI/CD](#transfer-your-files-from-cicd)

## Important notice

Configuration scripts for deploy environment are meant to be executed after fresh installation of the OS.

Its purpose in not to be bullet-proof neither to handle all cases. It's just here to get started quickly as it just executes the exact same commands listed in "manual configuration" sections.

**So, if you have any trouble a non fresh-installed machine, please use "manual configuration" sections to complete your installation environment process.**

## Prerequisites

### Create a user account with sudo privileges

[Back to top ↑](#table-of-contents)

By default, if you install Ubuntu manually, it will ask you to create a user account with sudo privileges and disable root login automatically. This is how you are supposed to use your machine. This is because part of the power inherent with the root account is the ability to make very destructive changes, even by accident.

But, in most cases, the Ubuntu install process is handled by your hosting provider which gives you directly access to the root account. If you are in this case, follow these steps:

```bash
# Login to your machine's root account
ssh root@<hostname>

# Create a new user
adduser <username>

# Grant sudo privileges to the newly created user
usermod -aG sudo <username>

# Disable root login
passwd -l root

# Disconnect
exit
```

_SSH client is enabled by default on Windows since the 2018 April update (1804). Download the update if you have an error when using this command in PowerShell._

### Configure an SSH key

[Back to top ↑](#table-of-contents)

Before going any further, you need to generate an SSH key and add it to your server machine.

```bash
ssh-keygen -t rsa -b 4096 -N ''
```

Then add it to your machine by using:

```bash
ssh-copy-id <username>@<hostname>
```

_Note: replace "username" and "hostname" by your credentials infos._

**The following script will disable SSH password authentication for security reasons. You must backup the generated SSH key in a safe place (for example, in a password manager app) to prevent loosing access to the machine if your computer dies.**

## Quickstart

[Back to top ↑](#table-of-contents)

### Server setup

```bash
# Get and execute script directly
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy/master/ubuntu18.04_configure_deploy_env.sh)"
```

This will install all softwares needed to host production apps.

### Configure a new app

#### HTML/JS/React/Angular

```bash
# Get and execute script directly
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy-ubuntu/master/ubuntu18.04_deploy_htmljsreactangular_app.sh)"
```

#### PHP/Symfony

```bash
# Get and execute script directly
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy-ubuntu/master/ubuntu18.04_deploy_phpsymfony_app.sh)"
```

#### Connecting to your app

The previous scripts will create the web server configuration, the database and the SSH user for your app (based on your app name). After that, you will be able to login to your app with:

```bash
ssh -p 3022 <appname>@<hostname>
```

If you need to deploy your app through CI & CD, follow [these instructions](#transfer-your-files-from-cicd).

## Manual configuration: server setup

### Set up variables

[Back to top ↑](#table-of-contents)

```bash
# Ask email if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${email}" ]]; then
    read -r -p "Enter your email (needed to set up email monitoring): " email
fi
```

### SSH

[Back to top ↑](#table-of-contents)

We will disable SSH password authentication, this will prevent all non authorized computers from being able to access the machine through SSH.

**You must have completed the [Configure an SSH Key](#configure-an-ssh-key) section before completing these steps or you will loose access to your machine.**

```bash
# Change default port
sudo sed -i'.backup' -e 's/#Port 22/Port 3022/g' /etc/ssh/sshd_config

# Disable password authentication
sudo sed -i'.backup' -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# Disable root login
sudo sed -i'.backup' -e 's/#PermitRootLogin prohibit-password/PermitRootLogin no/g' /etc/ssh/sshd_config
sudo sed -i'.backup' -e 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sudo sed -i'.backup' -e 's/#PermitRootLogin no/PermitRootLogin no/g' /etc/ssh/sshd_config

# Keep alive client connections
echo "
ClientAliveInterval 120
ClientAliveCountMax 3" | sudo tee -a /etc/ssh/sshd_config > /dev/null

# Restart SSH
sudo service ssh restart
```

### Updates

[Back to top ↑](#table-of-contents)

Enabling automatic updates ensures that the server gets all security and software fixes as they are published.

```bash
# Install latest updates
sudo apt update && sudo apt dist-upgrade -y

# Make a backup of the config files
sudo cp /etc/apt/apt.conf.d/10periodic /etc/apt/apt.conf.d/.10periodic.backup
sudo cp /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/.50unattended-upgrades.backup

# Download updates when available
sudo sed -i'.tmp' -e 's,APT::Periodic::Download-Upgradeable-Packages "0";,APT::Periodic::Download-Upgradeable-Packages "1";,g' /etc/apt/apt.conf.d/10periodic

# Clean apt cache every week
sudo sed -i'.tmp' -e 's,APT::Periodic::AutocleanInterval "0";,APT::Periodic::AutocleanInterval "7";,g' /etc/apt/apt.conf.d/10periodic

# Enable automatic updates once downloaded
sudo sed -i'.tmp' -e 's,//\s"${distro_id}:${distro_codename}-updates";,        "${distro_id}:${distro_codename}-updates";,g' /etc/apt/apt.conf.d/50unattended-upgrades

# Enable email notifications
sudo sed -i'.tmp' -e "s,//Unattended-Upgrade::Mail \"root\";,Unattended-Upgrade::Mail \"${email}\";,g" /etc/apt/apt.conf.d/50unattended-upgrades

# Enable email notifications only on failures
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::MailOnlyOnError "true";,Unattended-Upgrade::MailOnlyOnError "true";,g' /etc/apt/apt.conf.d/50unattended-upgrades

# Remove unused kernel packages when needed
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::Remove-Unused-Kernel-Packages "false";,Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";,g' /etc/apt/apt.conf.d/50unattended-upgrades

# Remove unused dependencies when needed
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::Remove-Unused-Dependencies "false";,Unattended-Upgrade::Remove-Unused-Dependencies "true";,g' /etc/apt/apt.conf.d/50unattended-upgrades

# Reboot when needed
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::Automatic-Reboot "false";,Unattended-Upgrade::Automatic-Reboot "true";,g' /etc/apt/apt.conf.d/50unattended-upgrades

# Set reboot time to 3 AM
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::Automatic-Reboot-Time "02:00";,Unattended-Upgrade::Automatic-Reboot-Time "03:00";,g' /etc/apt/apt.conf.d/50unattended-upgrades

# Remove temporary files
sudo rm /etc/apt/apt.conf.d/10periodic.tmp
sudo rm /etc/apt/apt.conf.d/50unattended-upgrades.tmp
```

### Postfix

[Back to top ↑](#table-of-contents)

We've set up email notifications on updates errors but we need an SMTP server in order to actually be able to send emails.

```bash
# Install
sudo DEBIAN_FRONTEND=noninteractive apt install -y postfix mailutils

# Make a backup of the config file
sudo cp /etc/aliases /etc/.aliases.backup

# Forwarding System Mail to your email address
echo "root:     ${email}" | sudo tee -a /etc/aliases > /dev/null
sudo newaliases
```

### Apache 2

[Back to top ↑](#table-of-contents)

```bash
# Install
sudo apt install -y apache2

# Enable modules
sudo a2enmod ssl
sudo a2enmod rewrite

# Set umask of the Apache user
echo "umask 002" | sudo tee -a /etc/apache2/envvars > /dev/null

# Restart Apache
sudo service apache2 restart
```

**Installed modules:** core_module, so_module, watchdog_module, http_module, log_config_module, logio_module, version_module, unixd_module, access_compat_module, alias_module, auth_basic_module, authn_core_module, authn_file_module, authz_core_module, authz_host_module, authz_user_module, autoindex_module, deflate_module, dir_module, env_module, filter_module, mime_module, mpm_event_module, negotiation_module, reqtimeout_module, rewrite_module, setenvif_module, socache_shmcb_module, ssl_module, status_module

### Certbot

[Back to top ↑](#table-of-contents)

In order to get SSL certifications, we need certbot.

```bash
# Add Certbot official repositories
sudo add-apt-repository universe
sudo add-apt-repository -y ppa:certbot/certbot

# Install
sudo apt install -y certbot

# Check certificates renewal every month
echo '#!/bin/bash
certbot renew' | sudo tee /etc/cron.monthly/certbot-renew.sh > /dev/null
sudo chmod +x /etc/cron.monthly/certbot-renew.sh

# Disable default site
sudo a2dissite 000-default.conf
```

### Firewall

[Back to top ↑](#table-of-contents)

We will enable Ubuntu firewall in order to prevent remote access to our machine. We will only allow SSH (for remote SSH access), Postfix (for emails sent to the postmaster address) and Apache2 (for remote web access). **Careful, you need to allow SSH before enabling the firewall, if not, you may lose access to your machine.**

```bash
# Add rules and activate firewall
sudo ufw allow 3022
sudo ufw allow Postfix
sudo ufw allow in "Apache Full"
echo 'y' | sudo ufw enable
```

### Fail2ban

[Back to top ↑](#table-of-contents)

Preventing remote access from others sotwares than SSH, Postfix and Apache in not enough. We are still vulnerable to brute-force attacks through these services. We will use Fail2ban to protect us.

```bash
# Install
sudo apt install -y fail2ban

# Add default configuration
echo "[DEFAULT]
findtime = 3600
bantime = 86400
destemail = ${email}
action = %(action_mwl)s" | sudo tee /etc/fail2ban/jail.local > /dev/null

echo "
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3" | sudo tee -a /etc/fail2ban/jail.local > /dev/null

# Add Postfix configuration
echo "
[postfix]
enabled  = true
port     = smtp
filter   = postfix
logpath  = /var/log/mail.log
maxretry = 5" | sudo tee -a /etc/fail2ban/jail.local > /dev/null

# Add Apache configuration
echo "
[apache]
enabled  = true
port     = http,https
filter   = apache-auth
logpath  = /var/log/apache*/*error.log
maxretry = 6

[apache-noscript]
enabled  = true
port     = http,https
filter   = apache-noscript
logpath  = /var/log/apache*/*error.log
maxretry = 6

[apache-overflows]
enabled  = true
port     = http,https
filter   = apache-overflows
logpath  = /var/log/apache*/*error.log
maxretry = 2

[apache-nohome]
enabled  = true
port     = http,https
filter   = apache-nohome
logpath  = /var/log/apache*/*error.log
maxretry = 2

[apache-botsearch]
enabled  = true
port     = http,https
filter   = apache-botsearch
logpath  = /var/log/apache*/*error.log
maxretry = 2

[apache-shellshock]
enabled  = true
port     = http,https
filter   = apache-shellshock
logpath  = /var/log/apache*/*error.log
maxretry = 2

[apache-fakegooglebot]
enabled  = true
port     = http,https
filter   = apache-fakegooglebot
logpath  = /var/log/apache*/*error.log
maxretry = 2

[php-url-fopen]
enabled = true
port    = http,https
filter  = php-url-fopen
logpath = /var/log/apache*/*access.log" | sudo tee -a /etc/fail2ban/jail.local > /dev/null

# Restart Fail2ban
sudo service fail2ban restart
```

### PHP environment (optional)

[Back to top ↑](#table-of-contents)

```bash
# Add PHP official repository
sudo add-apt-repository -y ppa:ondrej/php

# Install PHP
sudo apt install -y php7.3

# Install extensions
sudo apt install -y php7.3-mbstring php7.3-mysql php7.3-xml php7.3-curl php7.3-zip php7.3-intl php7.3-gd

# Make a backup of the config file
phpinipath=$(php -r "echo php_ini_loaded_file();")
sudo cp "${phpinipath}" "$(dirname "${phpinipath}")/.php.ini.backup"

# Update some configuration in php.ini
sudo sed -i'.tmp' -e 's/post_max_size = 8M/post_max_size = 64M/g' "${phpinipath}"
sudo sed -i'.tmp' -e 's/upload_max_filesize = 8M/upload_max_filesize = 64M/g' "${phpinipath}"
sudo sed -i'.tmp' -e 's/memory_limit = 128M/memory_limit = 512M/g' "${phpinipath}"

# Disable functions that can causes security breaches
sudo sed -i'.tmp' -e 's/disable_functions =/disable_functions = error_reporting,ini_set,exec,passthru,shell_exec,system,proc_open,popen,parse_ini_file,show_source/g' "${phpinipath}"

# Replace default PHP installation in $PATH
sudo update-alternatives --set php /usr/bin/php7.3

# Remove temporary file
sudo rm "${phpinipath}.tmp"

# Apply PHP configuration to Apache
sudo cp /etc/php/7.3/apache2/php.ini /etc/php/7.3/apache2/.php.ini.backup
sudo cp "${phpinipath}" /etc/php/7.3/apache2/php.ini

# Add MariaDB official repository
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo -E bash

# Install
sudo apt install -y mariadb-server-10.4
```

### NodeJS environment (optional)

[Back to top ↑](#table-of-contents)

```bash
# Add NodeJS official repository and update packages list
curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -

# Install
sudo apt install -y nodejs

# Install PM2 process manager
sudo npm install -g pm2@4.4.0

# Add MariaDB official repository
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo -E bash

# Install
sudo apt install -y mariadb-server-10.4
```

## Manual configuration: configure an HTML/JS/React/Angular app

### Set up variables for HTML/JS/React/Angular app configuration

[Back to top ↑](#table-of-contents)

We need to configure some variables in order to reduce repetitions/replacements in the next commands.

```bash
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
```

### Set up the web server for HTML/JS/React/Angular app

[Back to top ↑](#table-of-contents)

```bash
# Create the app directory
sudo mkdir "/var/www/${appname}"

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

    # Set up React/Angular specific configuration
    <Directory />
        Require all denied
    </Directory>
    <Directory /var/www/${appname}>
        Require all granted
        Options None
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

# Activate app conf
sudo a2ensite "${appname}.conf"

# Restart Apache to make changes available
sudo service apache2 restart
```

## Manual configuration: configure a NodeJS/NestJS app

### Set up variables for NodeJS/NestJS app configuration

[Back to top ↑](#table-of-contents)

We need to configure some variables in order to reduce repetitions/replacements in the next commands.

```bash
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

# Ask localport if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${localport}" ]]; then
    read -r -p "Enter the running local port on which you want requests to be proxied (eg. 3000): " localport
fi

# Ask database password (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${mysqlpassword}" ]]; then
    read -r -p "Enter the database password you want for your app (save it in a safe place): " mysqlpassword
fi
```

### Set up the web server for NodeJS/NestJS app

[Back to top ↑](#table-of-contents)

```bash
# Create the app directory
sudo mkdir "/var/www/${appname}"

# Set ownership to Apache
sudo chown www-data:www-data "/var/www/${appname}"

# Activate letsencrypt-webroot conf
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
    <Directory /var/www/${appname}>
        Require all granted
        Options None
        ProxyPass "/" "http://localhost:${localport}/"
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
```

### Set up the SQL database

[Back to top ↑](#table-of-contents)

```bash
# Create database and related user for the app and grant permissions
sudo mysql -e "CREATE DATABASE ${appname};
CREATE USER ${appname}@localhost IDENTIFIED BY '${mysqlpassword}';
GRANT ALL ON ${appname}.* TO ${appname}@localhost;"
```

## Manual configuration: configure a PHP/Symfony app

### Set up variables for PHP/Symfony app configuration

[Back to top ↑](#table-of-contents)

We need to configure some variables in order to reduce repetitions/replacements in the next commands.

```bash
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
```

### Set up the web server for PHP/Symfony app

[Back to top ↑](#table-of-contents)

```bash
# Create the app directory
sudo mkdir "/var/www/${appname}"

# Set ownership to Apache
sudo chown www-data:www-data "/var/www/${appname}"

# Activate letsencrypt-webroot conf
sudo a2ensite 000-default.conf

# Restart Apache to make changes available
sudo service apache2 restart

# Get a new HTTPS certficate
sudo certbot certonly --webroot -w /var/www/html -d "${appdomain}" -m "${email}" -n --agree-tos

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
```

### Set up the SQL database

[Back to top ↑](#table-of-contents)

```bash
# Create database and related user for the app and grant permissions
sudo mysql -e "CREATE DATABASE ${appname};
CREATE USER ${appname}@localhost IDENTIFIED BY '${mysqlpassword}';
GRANT ALL ON ${appname}.* TO ${appname}@localhost;"
```

## Manual configuration: suite (all apps)

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

# Give Apache group to the user (so that Apache can still access his files)
sudo usermod -g www-data "${appname}"

# Create SSH folder in the user home
sudo mkdir -p "/home/${appname}/.ssh"

# Copy the authorized_keys file to enable passwordless SSH connections
sudo cp ~/.ssh/authorized_keys "/home/${appname}/.ssh/authorized_keys"

# Give ownership to the user
sudo chown -R "${appname}:${appname}" "/home/${appname}/.ssh"
```

**Note: you actually don't need to know the password because we disabled SSH password authentication and didn't give sudo privileges to this user.**

### Create a chroot jail for this user

[Back to top ↑](#table-of-contents)

Because we only want this user to access his app and nothing else.

```bash
# Create the jail
sudo username="${appname}" use_basic_commands=n bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/chroot-jail/master/create.sh)"

# Mount the app folder into the jail
sudo mount --bind "/var/www/${appname}" "/home/jails/${appname}/home/${appname}"

# Make the mount permanent
echo "/var/www/${appname} /home/jails/${appname}/home/${appname} ext4 rw,relatime,data=ordered 0 0" | sudo tee -a /etc/fstab > /dev/null
```

**Note: this user must be used to access and manage your app safely. He cannot access other apps nor system settings.**

After that, you will be able to login to your app with:

```bash
ssh -p 3022 <appname>@<hostname>
```

### Transfer your files from your computer

[Back to top ↑](#table-of-contents)

All you need to do now is to transfer your app files using the SSH user created for your app (in the home directory) through SFTP or SSH.

You can use the [Filezilla FTP client](https://filezilla-project.org/) or automate the process using a tool like [Rsync](https://linux.die.net/man/1/rsync).

Don’t forget to only install production dependencies and to configure environment variables in the `.env.local` file (if you're using DotENV) before transferring your files.

### Transfer your files from CI/CD

[Back to top ↑](#table-of-contents)

Using our private key directly on a machine owned by a Continuous Integration & Continuous Delivery (CI & CD) service provider (such as GitHub Actions, GitLab, Jenkins, Travis, etc.) is **INSECURED**.

All your machines probably accept this private key, because, well, you are the admin.

You don't know how the CI & CD services will store your key (even if they claimed they are secured). The risk is that if your private key is compromised and stolen, all your machines will be opened to the thief.

Instead, we will create a new SSH private/public key pair that will be **dedicated to the CI & CD usage of this app**. If it's compromised, only this app can be damaged and you can easily revoke it from the production server without removing your own access.

From your local computer, create a new SSH keys for you app (replace "appname"):

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/<appname>.id_rsa -C '<appname>'
```

Then, **backup the content of these files** (in a password manager app for example).

You can add the key to the SSH user of the app with:

```bash
ssh -p 3022 -t <adminusername>@<hostname> "echo '$(cat ~/.ssh/<appname>.id_rsa.pub)' | sudo tee -a /home/<appname>/.ssh/authorized_keys"
```

You can then safely copy this private key to the CI & CD service provider of your choice.
