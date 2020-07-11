# The web deploy instructions kit

The purpose of this repository is to provide instructions to configure a web deployment environment.

The goal is to provide an opinionated, fully tested environment, that just work.

## Table of contents

- [Important notice](#important-notice)
- [Prerequisites](#prerequisites)
  - [Create a user account with sudo privileges](#create-a-user-account-with-sudo-privileges)
  - [Configure an SSH key](#configure-an-ssh-key)
  - [Point your domain names to your machine IP address](#point-your-domain-names-to-your-machine-ip-address)
- [Quickstart](#quickstart)
- [Transfer your files from your computer](#transfer-your-files-from-your-computer)
- [Transfer your files from CI/CD](#transfer-your-files-from-cicd)

## Important notice

Configuration scripts are meant to be executed after fresh installation of the OS.

## Prerequisites

### Create a user account with sudo privileges

[Back to top ↑](#table-of-contents)

By default, if you install Ubuntu manually, it will ask you to create a user account with sudo privileges and disable root login automatically. This is how you are supposed to use your machine. This is because part of the power inherent with the root account is the ability to make very destructive changes, even by accident.

But, in most cases, the Ubuntu install process is handled by your hosting provider which gives you directly access to the root account. If you are in this case, follow these steps:

```bash
# Login to your machine's root account
ssh root@<ipAddress>

# Create a new user
adduser <username>

# Grant sudo privileges to the newly created user
usermod -aG sudo <username>

# Disable root password
passwd -l root

# Disconnect
exit
```

Sometimes, Ubuntu comes already preinstalled with a non-root sudo user named "ubuntu". In that case, you probably just want to rename it before using it:

```bash
# Login to your machine's "ubuntu" account
ssh ubuntu@<ipAddress>

# Define a password for the root account
sudo passwd root

# Allow root login with password through SSH
sudo sed -i'.backup' -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config

# Restart SSH
sudo service ssh restart

# Disconnect from your machine
exit

# Login to your machine's root account
ssh root@<ipAddress>

# Rename user
usermod -l <newUserName> ubuntu

# Rename home directory
usermod -d /home/<newUserName> -m <newUserName>

# Change password
passwd <newUserName>

# Disable root password
sudo passwd -l root

# Disallow root login with password through SSH
sudo sed -i'.backup' -e 's/PermitRootLogin yes/#PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config

# Restart SSH
sudo service ssh restart

# Disconnect from your machine
exit
```

_SSH client is enabled by default on Windows since the 2018 April update (1804). Download the update if you have an error when using SSH command in PowerShell._

### Configure an SSH key

[Back to top ↑](#table-of-contents)

Before going any further, you need to generate an SSH key and add it to your server machine.

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa
```

Then add it to your machine by using:

```bash
ssh <yourUserName>@<yourIpAddress> "echo '$(cat ~/.ssh/id_rsa.pub)' | tee -a ~/.ssh/authorized_keys > /dev/null && chmod 400 ~/.ssh/id_rsa*"
```

### Point your domain names to your machine IP address

[Back to top ↑](#table-of-contents)

Before continuing, your machine needs to have a dedicated domain name that will be its hostname.

You also need to point your app domain names to your machine IP address if you want to host an app for them. See with your domain name registrar to set up A (IPV4) or AAAA (IPV6) records to perform this operation.

A minimal DNS zone typically looks like this:

![minimal-dns-zone](https://user-images.githubusercontent.com/6952638/84637979-ae703b00-aef6-11ea-8343-0f2036609a6c.png)

For example, after that, you will be able to login with:

```bash
ssh <username>@mymachine.example.com
```

Instead of:

```bash
ssh <username>@50.70.150.30
```

## Quickstart

[Back to top ↑](#table-of-contents)

Login to your machine's sudo user and run the following commands.

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
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy/master/ubuntu18.04_deploy_htmljsreactangular_app.sh)"
```

#### NodeJS/NestJS

```bash
# Get and execute script directly
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy/master/ubuntu18.04_deploy_nodejsnestjs_app.sh)"
```

#### PHP/Symfony

```bash
# Get and execute script directly
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy/master/ubuntu18.04_deploy_phpsymfony_app.sh)"
```

#### PHP/Nextcloud

```bash
# Get and execute script directly
bash -c "$(wget --no-cache -O- https://raw.githubusercontent.com/RomainFallet/web-deploy/master/ubuntu18.04_deploy_phpnextcloud_app.sh)"
```

#### Connecting to your app

The previous scripts will create the web server configuration, the database and the SSH user for your app (based on your app name). After that, you will be able to login to your app with:

```bash
ssh -p 3022 <appname>@<hostname>
```

If you need to deploy your app through CI & CD, follow [these instructions](#transfer-your-files-from-cicd).

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

From your local computer, create new SSH keys for you app (replace "appname"):

```bash
ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/<appname>.id_rsa -C '<appname>'
```

Then, **backup the content of these files** (in a password manager app for example).

You can add the key to the SSH user of the app with:

```bash
ssh -p 3022 -t <adminusername>@<hostname> "echo '$(cat ~/.ssh/<appname>.id_rsa.pub)' | sudo tee -a /home/<appname>/.ssh/authorized_keys"
```

You can then safely copy this private key to the CI & CD service provider of your choice.
