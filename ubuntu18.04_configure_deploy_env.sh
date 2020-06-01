#!/bin/bash

# Exit script on error
set -e

### Set up variables

# Ask email if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${email}" ]]; then
    read -r -p "Enter your email (needed to set up email monitoring): " email
fi

### SSH

# Change default port
sudo sed -i'.backup' -e 's/#Port 22/Port 3022/g' /etc/ssh/sshd_config

# Diable password authentication
sudo sed -i'.backup' -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# Disable root login
sudo sed -i'.backup' -e 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
sudo sed -i'.backup' -e 's/#PermitRootLogin no/PermitRootLogin no/g' /etc/ssh/sshd_config

# Keep alive client connections
echo "
ClientAliveInterval 120
ClientAliveCountMax 3" | sudo tee -a /etc/ssh/sshd_config > /dev/null

# Restart SSH
sudo service ssh restart

### Updates

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

### Postfix

# Install
sudo DEBIAN_FRONTEND=noninteractive apt install -y postfix mailutils

# Make a backup of the config file
sudo cp /etc/aliases /etc/.aliases.backup

# Forwarding System Mail to your email address
echo "root:     ${email}" | sudo tee -a /etc/aliases > /dev/null
sudo newaliases

postconf mail_version

### Apache 2

# Install
sudo apt install -y apache2

# Enable modules
sudo a2enmod ssl
sudo a2enmod rewrite

# Set umask of the Apache user
echo "umask 002" | sudo tee -a /etc/apache2/envvars > /dev/null

# Restart Apache
sudo service apache2 restart

apache2 -v
sudo apache2ctl -M

### Certbot

# Add Certbot official repositories
sudo add-apt-repository universe
sudo add-apt-repository -y ppa:certbot/certbot

# Install
sudo apt install -y certbot

certbot --version

### Firewall

# Add rules and activate firewall
sudo ufw allow 3022
sudo ufw allow Postfix
sudo ufw allow in "Apache Full"
echo 'y' | sudo ufw enable

sudo ufw status

### Fail2ban

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

fail2ban-client -V

### PHP/Symfony environment (optional)

# Ask for PHP/Symfony environment
if [[ -z "${phpsymfony}" ]]; then
    read -r -p "Do you want to install PHP environment? [N/y]: " phpsymfony
    phpsymfony=${phpsymfony:-n}
    phpsymfony=$(echo "${phpsymfony}" | awk '{print tolower($0)}')
fi

if [[ "${phpsymfony}" == 'y' ]]; then
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
fi
