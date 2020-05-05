# The web deploy instructions kit

![logo-ubuntu](https://user-images.githubusercontent.com/6952638/78182032-b119d300-7465-11ea-9e00-43e3d7265f91.png)

The purpose of this repository is to provide instructions to configure a web deployment environment on **Ubuntu 18.04 Server**.

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
    9. [PHP/Symfony environment (optional)](#phpsymfony-environment-optional)
- [Manual configuration: deploy a PHP/Symfony app](#manual-configuration-deploy-a-phpsymfony-app)
    1. [Set up variables for PHP/Symfony app deployment](#set-up-variables-for-phpsymfony-app-deployment)
    2. [Clone the app](#clone-the-app)
    3. [Set up the database and the production mode](#set-up-the-database-and-the-production-mode)
    4. [Set permissions](#set-permissions)
    5. [Set up the web server](#set-up-the-web-server)
    6. [Enabling HTTPS & configure for Symfony](#enabling-https--configure-for-symfony)
    7. [Create a new SSH user for the app](#create-a-new-ssh-user-for-the-app)
    8. [Create a chroot jail for this user](#create-a-chroot-jail-for-this-user)
    9. [Enable passwordless SSH connections](#enable-passwordless-ssh-connections)
    10. [Init or update the app](#init-or-update-the-app)

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
ssh-copy-id -i ~/.ssh/id_rsa <username>@<hostname>
```

_Note: replace "username" and "hostname" by your credentials infos._

**The following script will disable SSH password authentication for security reasons. You must backup the generated SSH key in a safe place (for example, in a password manager app) to prevent loosing access to the machine if your computer dies.**

## Quickstart

[Back to top ↑](#table-of-contents)

### Server setup

```bash
# Get and execute script directly
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy-ubuntu/master/ubuntu18.04_configure_deploy_env.sh)"
```

### Deploy a new PHP/Symfony app

```bash
# Get and execute script directly
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy-ubuntu/master/ubuntu18.04_deploy_symfony_app.sh)"
```

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
# Diable password authentication
sudo sed -i'.backup' -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

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

# Restart Apache
sudo service apache2 restart
```

**Installed modules:** core_module, so_module, watchdog_module, http_module, log_config_module, logio_module, version_module, unixd_module, access_compat_module, alias_module, auth_basic_module, authn_core_module, authn_file_module, authz_core_module, authz_host_module, authz_user_module, autoindex_module, deflate_module, dir_module, env_module, filter_module, mime_module, mpm_event_module, negotiation_module, reqtimeout_module, rewrite_module, setenvif_module, socache_shmcb_module, ssl_module, status_module

### Certbot

[Back to top ↑](#table-of-contents)

In order to get SSL certifications, we need certbot.

Ubuntu 18.04 Server:

```bash
# Add Certbot official repositories
sudo add-apt-repository universe
sudo add-apt-repository -y ppa:certbot/certbot

# Install
sudo apt install -y certbot
```

### Firewall

[Back to top ↑](#table-of-contents)

We will enable Ubuntu firewall in order to prevent remote access to our machine. We will only allow SSH (for remote SSH access), Postfix (for emails sent to the postmaster address) and Apache2 (for remote web access). **Careful, you need to allow SSH before enabling the firewall, if not, you may lose access to your machine.**

```bash
# Add rules and activate firewall
sudo ufw allow OpenSSH
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

# Add SSH configuration
echo "[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3" | sudo tee /etc/fail2ban/jail.local > /dev/null

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

### PHP/Symfony environment (optional)

[Back to top ↑](#table-of-contents)

```bash
# Install PHP/Symfony dev environment
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/symfony-dev-deploy/master/ubuntu18.04_configure_dev_env.sh)"

# Get path to PHP config file
phpinipath=$(php -r "echo php_ini_loaded_file();")

# Disable functions that can causes security breaches
sudo sed -i'.tmp' -e 's/disable_functions =/disable_functions = error_reporting,ini_set,exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source/g' "${phpinipath}"

# Hide errors (can cause security issues)
sudo sed -i'.tmp' -e 's/display_errors = On/display_errors = Off/g' "${phpinipath}"
sudo sed -i'.tmp' -e 's/display_startup_errors = On/display_startup_errors = Off/g' "${phpinipath}"
sudo sed -i'.tmp' -e 's/error_reporting = E_ALL/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/g' "${phpinipath}"

# Remove temporary file
sudo rm "${phpinipath}.tmp"

# Disable Xdebug extension (can cause performance issues)
sudo phpdismod xdebug

# Apply PHP configuration to Apache
sudo cp /etc/php/7.3/apache2/php.ini /etc/php/7.3/apache2/.php.ini.backup
sudo mv "${phpinipath}" /etc/php/7.3/apache2/php.ini
```

## Manual configuration: deploy a PHP/Symfony app

### Set up variables for PHP/Symfony app deployment

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

# Ask repository URL if not already set (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${apprepositoryurl}" ]]; then
    read -r -p "Enter the Git repository URL of your app: " apprepositoryurl
fi

# Ask SSH password if not already set (copy and paste all stuffs from "if" to "fi" in your terminal)
if [[ -z "${sshpassword}" ]]; then
    read -r -p "Enter a new password for the SSH account that will be created for your app: " sshpassword
fi
```

### Clone the app

[Back to top ↑](#table-of-contents)

```bash
# Clone app repository
sudo git clone "${apprepositoryurl}" "/var/www/${appname}"

# Go inside the app directory
cd "/var/www/${appname}"
```

### Set up the database and the production mode

[Back to top ↑](#table-of-contents)

```bash
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
```

### Set permissions

[Back to top ↑](#table-of-contents)

```bash
# Set ownership to Apache
sudo chown -R www-data:www-data "/var/www/${appname}"

# Set files permissions to 664
sudo find "/var/www/${appname}" -type f -exec chmod 664 {} \;

# Set folders permissions to 775
sudo find "/var/www/${appname}" -type d -exec chmod 775 {} \;
```

### Set up the web server

[Back to top ↑](#table-of-contents)

```bash
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
```

### Enabling HTTPS & configure for Symfony

[Back to top ↑](#table-of-contents)

```bash
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
```

### Create a new SSH user for the app

[Back to top ↑](#table-of-contents)

This user will be used to access the app.

```bash
# Encrypt the password
sshencryptedpassword=$(echo "${sshpassword}" | openssl passwd -crypt -stdin)

# Create the user and set the default shell
sudo useradd -m -p "${sshencryptedpassword}" -s /bin/bash "${appname}"

# Give ownership to the user
sudo chown -R "${appname}:www-data" "/var/www/${appname}"

# Clear history for security reasons
unset HISTFILE
history -c
```

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

**Note: this user must be used to access and manage your app. It has access to every tool you need (php, composer, git...) and cannot access other apps nor system settings.**

### Init or update the app

[Back to top ↑](#table-of-contents)

**Note: you must login with the newly created app SSH account to run these commands to ensure that the generated files will have appropriate permissions.**

```bash
# Go inside the app directory
cd ~/

# Get latest updates
git pull

# Install PHP dependencies
composer install

# Install JS dependencies if package.json is found
yarn install

# Build assets if build script is found
yarn build

# Execute database migrations
php bin/console doctrine:migrations:diff --allow-empty-diff
php bin/console doctrine:migrations:migrate -n
```
