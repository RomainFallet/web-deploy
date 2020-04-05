#!/bin/bash

### Set up variables

# Ask email if not already set (copy and paste all stuffs between "if" and "fi" in your terminal)
if [[ -z "${email}" ]]; then
    read -r -p "Enter your email (needed to set up email monitoring): " email || exit 1
fi

### SSH

# Diable password authentication
sudo sed -i'.backup' -e 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config  || exit 1

# Keep alive client connections
echo "
ClientAliveInterval 120
ClientAliveCountMax 3" | sudo tee -a /etc/ssh/sshd_config > /dev/null || exit 1

# Restart SSH
sudo service ssh restart || exit 1

### Updates

# Install latest updates
sudo apt update && sudo apt dist-upgrade -y || exit 1

# Make a backup of the config files
sudo cp /etc/apt/apt.conf.d/10periodic /etc/apt/apt.conf.d/.10periodic.backup || exit 1
sudo cp /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/.50unattended-upgrades.backup || exit 1

# Download updates when available
sudo sed -i'.tmp' -e 's,APT::Periodic::Download-Upgradeable-Packages "0";,APT::Periodic::Download-Upgradeable-Packages "1";,g' /etc/apt/apt.conf.d/10periodic || exit 1

# Clean apt cache every week
sudo sed -i'.tmp' -e 's,APT::Periodic::AutocleanInterval "0";,APT::Periodic::AutocleanInterval "7";,g' /etc/apt/apt.conf.d/10periodic || exit 1

# Enable automatic updates once downloaded
sudo sed -i'.tmp' -e 's,//\s"${distro_id}:${distro_codename}-updates";,        "${distro_id}:${distro_codename}-updates";,g' /etc/apt/apt.conf.d/50unattended-upgrades || exit 1

# Enable email notifications
sudo sed -i'.tmp' -e "s,//Unattended-Upgrade::Mail \"root\";,Unattended-Upgrade::Mail \"${email}\";,g" /etc/apt/apt.conf.d/50unattended-upgrades || exit 1

# Enable email notifications only on failures
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::MailOnlyOnError "true";,Unattended-Upgrade::MailOnlyOnError "true";,g' /etc/apt/apt.conf.d/50unattended-upgrades || exit 1

# Remove unused kernel packages when needed
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::Remove-Unused-Kernel-Packages "false";,Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";,g' /etc/apt/apt.conf.d/50unattended-upgrades || exit 1

# Remove unused dependencies when needed
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::Remove-Unused-Dependencies "false";,Unattended-Upgrade::Remove-Unused-Dependencies "true";,g' /etc/apt/apt.conf.d/50unattended-upgrades || exit 1

# Reboot when needed
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::Automatic-Reboot "false";,Unattended-Upgrade::Automatic-Reboot "true";,g' /etc/apt/apt.conf.d/50unattended-upgrades || exit 1

# Set reboot time to 3 AM
sudo sed -i'.tmp' -e 's,//Unattended-Upgrade::Automatic-Reboot-Time "02:00";,Unattended-Upgrade::Automatic-Reboot-Time "03:00";,g' /etc/apt/apt.conf.d/50unattended-upgrades || exit 1

# Remove temporary files
sudo rm /etc/apt/apt.conf.d/10periodic.tmp || exit 1
sudo rm /etc/apt/apt.conf.d/50unattended-upgrades.tmp || exit 1

### Postfix

# Install
sudo DEBIAN_FRONTEND=noninteractive apt install -y postfix mailutils || exit 1

# Make a backup of the config file
sudo cp /etc/aliases /etc/.aliases.backup || exit 1

# Forwarding System Mail to your email address
echo "root:     ${email}" | sudo tee -a /etc/aliases > /dev/null || exit 1
sudo newaliases || exit 1

postconf mail_version || exit

### Apache 2

# Install
sudo apt install -y apache2 || exit 1

# Enable modules
sudo a2enmod ssl || exit 1
sudo a2enmod rewrite || exit 1

# Restart Apache
sudo service apache2 restart || exit 1

apache2 -v
sudo apache2ctl -M

### Certbot

# Add Certbot official repositories
sudo add-apt-repository universe || exit 1
sudo add-apt-repository -y ppa:certbot/certbot || exit 1

# Install
sudo apt install -y certbot || exit 1

certbot --version || exit 1

### Firewall

# Add rules and activate firewall
sudo ufw allow OpenSSH || exit 1
sudo ufw allow Postfix || exit 1
sudo ufw allow in "Apache Full" || exit 1
echo 'y' | sudo ufw enable || exit 1

sudo ufw status || exit 1

### Fail2ban

# Install
sudo apt install -y fail2ban || exit 1

# Add SSH configuration
echo "[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/auth.log
maxretry = 3" | sudo tee -a /etc/fail2ban/jail.local > /dev/null || exit 1

# Add Postfix configuration
echo "
[postfix]
enabled  = true
port     = smtp
filter   = postfix
logpath  = /var/log/mail.log
maxretry = 5" | sudo tee -a /etc/fail2ban/jail.local > /dev/null || exit 1

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
logpath = /var/log/apache*/*access.log" | sudo tee -a /etc/fail2ban/jail.local > /dev/null || exit 1

# Restart Fail2ban
sudo service fail2ban restart || exit 1

fail2ban-client -V || exit 1
sudo fail2ban-client status || exit 1

### PHP/Symfony environment (optional)

# Ask for PHP/Symfony environment
if [[ -z "${phpsymfony}" ]]; then
    read -r -p "Do you want to install PHP/Symfony environment? [N/y]: " phpsymfony || exit 1
    phpsymfony=${phpsymfony:-n} || exit 1
    phpsymfony=$(echo "${phpsymfony}" | awk '{print tolower($0)}') || exit 1
fi

if [[ "${phpsymfony}" == 'y' ]]; then
  # Install PHP/Symfony dev environment
  bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/symfony-dev-ubuntu/master/ubuntu18.04_configure_dev_env.sh)" || exit 1

  # Get path to PHP config file
  phpinipath=$(php -r "echo php_ini_loaded_file();") || exit 1

  # Disable functions that can causes security breaches
  sudo sed -i'.tmp' -e 's/disable_functions =/disable_functions = error_reporting,ini_set,exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source/g' "${phpinipath}" || exit 1

  # Hide errors (can cause security issues)
  sudo sed -i'.tmp' -e 's/display_errors = On/display_errors = Off/g' "${phpinipath}" || exit 1
  sudo sed -i'.tmp' -e 's/display_startup_errors = On/display_startup_errors = Off/g' "${phpinipath}" || exit 1
  sudo sed -i'.tmp' -e 's/error_reporting = E_ALL/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/g' "${phpinipath}" || exit 1

  # Remove temporary file
  sudo rm "${phpinipath}.tmp" || exit 1

  # Disable Xdebug extension (can cause performance issues)
  sudo phpdismod xdebug || exit 1

  # Apply PHP configuration to Apache
  sudo cp /etc/php/7.3/apache2/php.ini /etc/php/7.3/apache2/.php.ini.backup || exit 1
  sudo mv "${phpinipath}" /etc/php/7.3/apache2/php.ini || exit 1
fi
