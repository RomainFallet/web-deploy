#!/bin/bash

# Exit script on error
set -e

### Set up variables

# Ask email if not already set
if [[ -z "${email}" ]]; then
    read -r -p "Enter your email (needed to set up email monitoring): " email
fi

# Ask hostname if not already set
if [[ -z "${hostname}" ]]; then
    read -r -p "Enter your hostname (it must be a domain name pointing to this machine IP address): " hostname
fi

# Ask for remote SMTP
if [[ -z "${remotesmtp}" ]]; then
    read -r -p "Do you want to send monitoring emails from a remote SMTP server (recommended) [Y/n]: " remotesmtp
    remotesmtp=${remotesmtp:-y}
    remotesmtp=$(echo "${remotesmtp}" | awk '{print tolower($0)}')

    if [[ "${remotesmtp}" == 'y' ]]; then
      # Ask SMTP hostname if not already set
      if [[ -z "${smtphostname}" ]]; then
          read -r -p "Enter your remote SMTP server hostname: " smtphostname
      fi

      # Ask SMTP port if not already set
      if [[ -z "${smtpport}" ]]; then
          read -r -p "Enter your remote SMTP server port: " smtpport
      fi

      # Ask SMTP username if not already set
      if [[ -z "${smtpusername}" ]]; then
          read -r -p "Enter your remote SMTP server username: " smtpusername
      fi

      # Ask SMTP username if not already set
      if [[ -z "${smtppassword}" ]]; then
          read -r -p "Enter your SMTP password: " smtppassword
      fi
    fi
fi

### Timezone

# Change timezone
sudo timedatectl set-timezone Europe/Paris

### Hostname

# Change hostname
sudo hostnamectl set-hostname "${hostname}"

### SSH

# Change default port
sshportconfig='Port 3022'
if ! sudo grep "^${sshportconfig}" /etc/ssh/sshd_config > /dev/null
then
  sudo sed -i'.backup' -E "s/#*Port\s+[0-9]+/${sshportconfig}/g" /etc/ssh/sshd_config
fi
if ! sudo grep "^${sshportconfig}" /etc/ssh/sshd_config > /dev/null
then
  echo "${sshportconfig}" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi

# Disable password authentication
sshpassconfig='PasswordAuthentication no'
sudo sed -i'.backup' -E "s/#*PasswordAuthentication\s+(\w+)/PasswordAuthentication no/g" /etc/ssh/sshd_config
if ! sudo grep "^${sshpassconfig}" /etc/ssh/sshd_config > /dev/null
then
  echo "${sshpassconfig}" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi

# Keep alive client connections
sshclientintervalconfig='ClientAliveInterval 120'
sudo sed -i'.backup' -E "s/#*ClientAliveInterval\s+([0-9]+)/ClientAliveInterval 120/g" /etc/ssh/sshd_config
if ! sudo grep "^${sshclientintervalconfig}" /etc/ssh/sshd_config > /dev/null
then
  echo "${sshclientintervalconfig}" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi

sshclientcountconfig='ClientAliveCountMax 3'
sudo sed -i'.backup' -E "s/#*ClientAliveCountMax\s+([0-9]+)/ClientAliveCountMax 3/g" /etc/ssh/sshd_config
if ! sudo grep "^${sshclientcountconfig}" /etc/ssh/sshd_config > /dev/null
then
  echo "${sshclientcountconfig}" | sudo tee -a /etc/ssh/sshd_config > /dev/null
fi

# Restart SSH
sudo service ssh restart

### Updates

# Install latest updates
sudo apt update && sudo apt dist-upgrade -y

# Make a backup of the config files
sudo cp /etc/apt/apt.conf.d/10periodic /etc/apt/apt.conf.d/.10periodic.backup
sudo cp /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/.50unattended-upgrades.backup

# Download upgradable packages automatically
echo "APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Download-Upgradeable-Packages \"1\";
APT::Periodic::AutocleanInterval \"7\";" | sudo tee /etc/apt/apt.conf.d/10periodic > /dev/null

# Install updates automatically
echo "Unattended-Upgrade::Allowed-Origins {
  \"\${distro_id}:\${distro_codename}\";
  \"\${distro_id}:\${distro_codename}-security\";
  \"\${distro_id}ESMApps:\${distro_codename}-apps-security\";
  \"\${distro_id}ESM:\${distro_codename}-infra-security\";
  \"\${distro_id}:\${distro_codename}-updates\";
};
Unattended-Upgrade::DevRelease \"false\";
Unattended-Upgrade::Mail \"${email}\";
Unattended-Upgrade::MailOnlyOnError \"true\";
Unattended-Upgrade::Remove-Unused-Kernel-Packages \"true\";
Unattended-Upgrade::Remove-Unused-Dependencies \"true\";
Unattended-Upgrade::Automatic-Reboot \"true\";
Unattended-Upgrade::Automatic-Reboot-Time \"05:00\";" | sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null

### Default umask

# Change default system umask
sudo sed -i'.backup' -E 's/UMASK(\s+)([0-9]+)/UMASK\1002/g' /etc/login.defs

### Postfix

# Install
sudo DEBIAN_FRONTEND=noninteractive apt install -y postfix mailutils

# Make a backup of the config files
sudo cp /etc/postfix/main.cf /etc/postfix/.main.cf.backup
sudo cp /etc/aliases /etc/.aliases.backup


if [[ "${remotesmtp}" == 'y' ]]; then
# Update main config file
echo "# See /usr/share/postfix/main.cf.dist for a commented, more complete version


# Debian specific:  Specifying a file name will cause the first
# line of that file to be used as the name.  The Debian default
# is /etc/mailname.
#myorigin = /etc/mailname

smtpd_banner = \$myhostname ESMTP \$mail_name (Ubuntu)
biff = no

# appending .domain is the MUA's job.
append_dot_mydomain = no

# Uncomment the next line to generate \"delayed mail\" warnings
#delay_warning_time = 4h

readme_directory = no

# See http://www.postfix.org/COMPATIBILITY_README.html -- default to 2 on
# fresh installs.
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

# See /usr/share/doc/postfix/TLS_README.gz in the postfix-doc package for
# information on enabling SSL in the smtp client.

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = ${hostname}
relayhost = [${smtphostname}]:${smtpport}
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
inet_protocols = ipv4
smtp_sasl_auth_enable = yes
smtp_sasl_security_options = noanonymous
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_use_tls = yes
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt
sender_canonical_classes = envelope_sender, header_sender
sender_canonical_maps =  regexp:/etc/postfix/sender_canonical_maps
smtp_header_checks = regexp:/etc/postfix/header_check" | sudo tee /etc/postfix/main.cf > /dev/null

# Save SMTP credentials
echo "[${smtphostname}]:${smtpport} ${smtpusername}:${smtppassword}" | sudo tee /etc/postfix/sasl_passwd > /dev/null
sudo postmap /etc/postfix/sasl_passwd
sudo chown root:root /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db
sudo chmod 0600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db

# Remap sender address
echo "/.+/    ${smtpusername}" | sudo tee /etc/postfix/sender_canonical_maps > /dev/null
echo "/From:.*/ REPLACE From: ${smtpusername}" | sudo tee /etc/postfix/header_check > /dev/null
sudo postmap /etc/postfix/sender_canonical_maps
sudo postmap /etc/postfix/header_check
fi

# Forwarding System Mail to your email address
echo "root:     ${email}" | sudo tee -a /etc/aliases > /dev/null

# Enable aliases
sudo newaliases

# Restart Postfix
sudo service postfix restart

# Display Postfix version
postconf mail_version

echo "Email monitoring is enabled for your machine: ${hostname}." | mail -s "Email monitoring is enabled." "${email}"

### Apache web server (optional)

# Ask for apache
if [[ -z "${apache}" ]]; then
    read -r -p "Do you want to install Apache webserver & other related utilities? [N/y]: " apache
    php=${apache:-n}
    php=$(echo "${apache}" | awk '{print tolower($0)}')
fi

if [[ "${apache}" == 'y' ]]; then
# Install
sudo apt install -y apache2

# Enable modules
sudo a2enmod ssl
sudo a2enmod rewrite
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod headers

# Set umask of the Apache user
umaskconfig='umask 002'
if ! sudo grep "^${umaskconfig}" /etc/apache2/envvars > /dev/null
then
  echo "${umaskconfig}" | sudo tee -a /etc/apache2/envvars > /dev/null
fi

# Disable default site
sudo a2dissite 000-default.conf

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

# Check certificates renewal every month
echo '#!/bin/bash
certbot renew' | sudo tee /etc/cron.monthly/certbot-renew.sh > /dev/null
sudo chmod +x /etc/cron.monthly/certbot-renew.sh

certbot --version
fi

### Firewall

# Add rules and activate firewall
sudo ufw allow 3022
sudo ufw allow Postfix
"${apache}" == 'y' && sudo ufw allow in "Apache Full"
echo 'y' | sudo ufw enable

sudo ufw status

### Fail2ban

# Install
sudo apt install -y fail2ban

# Add default configuration
fail2banconfig="[DEFAULT]
findtime = 3600
bantime = 86400
destemail = ${email}
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3

[postfix]
enabled  = true
port     = smtp
filter   = postfix
logpath  = /var/log/mail.log
maxretry = 5
"

if [[ "${apache}" == 'y' ]]; then
fail2banconfig+="
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
logpath = /var/log/apache*/*access.log"
fi

echo "${fail2banconfig}" | sudo tee /etc/fail2ban/jail.local > /dev/null

# Restart Fail2ban
sudo service fail2ban restart

fail2ban-client -V

### PHP environment (optional)

# Ask for PHP/ environment
if [[ -z "${php}" ]]; then
    read -r -p "Do you want to install PHP environment? [N/y]: " php
    php=${php:-n}
    php=$(echo "${php}" | awk '{print tolower($0)}')
fi

if [[ "${php}" == 'y' ]]; then
  # Add PHP official repository
  sudo add-apt-repository -y ppa:ondrej/php

  # Install PHP
  sudo apt install -y php7.3

  # Install Redis for PHP cache
  sudo apt install -y redis-server

  # Install extensions
  sudo apt install -y php7.3-mbstring php7.3-mysql php7.3-xml php7.3-curl php7.3-zip php7.3-intl php7.3-gd php-redis

  # Make a backup of the config file
  phpinipath=$(php -r "echo php_ini_loaded_file();")
  sudo cp "${phpinipath}" "$(dirname "${phpinipath}")/.php.ini.backup"

  # Update some configuration in php.ini
  sudo sed -i'.tmp' -E 's/;*\s*post_max_size\s=\s*[0-8]+M/post_max_size = 64M/g' "${phpinipath}"
  sudo sed -i'.tmp' -E 's/;*\s*upload_max_filesize\s=\s*[0-8]+M/upload_max_filesize = 64M/g' "${phpinipath}"
  sudo sed -i'.tmp' -E 's/;*\s*memory_limit\s=\s*-*[0-8]+M*/memory_limit = 512M/g' "${phpinipath}"

  # Disable functions that can causes security breaches
  sudo sed -i'.tmp' -E 's/;*\s*disable_functions\s=\s*(\w+)/disable_functions = error_reporting,ini_set,exec,passthru,shell_exec,system,proc_open,popen,parse_ini_file,show_source/g' "${phpinipath}"

  # Replace default PHP installation in $PATH
  sudo update-alternatives --set php /usr/bin/php7.3

  # Remove temporary file
  sudo rm "${phpinipath}.tmp"

  # Apply PHP configuration to Apache
  sudo cp /etc/php/7.3/apache2/php.ini /etc/php/7.3/apache2/.php.ini.backup
  sudo cp "${phpinipath}" /etc/php/7.3/apache2/php.ini

  # Add MariaDB official repository
  test -f /etc/apt/sources.list.d/mariadb.list || curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo -E bash

  # Install
  sudo apt install -y mariadb-server-10.4
fi

### NodeJS environment (optional)

# Ask for NodeJS environment
if [[ -z "${nodejs}" ]]; then
    read -r -p "Do you want to install NodeJS environment? [N/y]: " nodejs
    nodejs=${nodejs:-n}
    nodejs=$(echo "${nodejs}" | awk '{print tolower($0)}')
fi

if [[ "${nodejs}" == 'y' ]]; then
  # Add NodeJS official repository and update packages list
  curl -sL https://deb.nodesource.com/setup_12.x | sudo -E bash -

  # Install
  sudo apt install -y nodejs

  # Install PM2 process manager
  sudo npm install -g pm2@4.4.0

  # Add MariaDB official repository
  test -f /etc/apt/sources.list.d/mariadb.list || curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo -E bash -s -- --mariadb-server-version=mariadb-10.4

  # Install
  sudo apt install -y mariadb-server-10.4
fi
