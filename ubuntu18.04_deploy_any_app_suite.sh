#!/bin/bash

### Create a new SSH user for the app

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

### Create a chroot jail for this user

# Create the jail
sudo username="${appname}" use_basic_commands=n bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/chroot-jail/master/create.sh)"

# Mount the app folder into the jail
sudo mount --bind "/var/www/${appname}" "/home/jails/${appname}/home/${appname}"

# Make the mount permanent
echo "/var/www/${appname} /home/jails/${appname}/home/${appname} ext4 rw,relatime,data=ordered 0 0" | sudo tee -a /etc/fstab > /dev/null
