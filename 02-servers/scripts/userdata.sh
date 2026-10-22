#!/bin/bash

set -euo pipefail

# Centralized logging
LOG=/root/userdata.log
mkdir -p /root
touch "$LOG"
chmod 600 "$LOG"
exec > >(tee -a "$LOG" | logger -t user-data -s 2>/dev/console) 2>&1
trap 'echo "ERROR at line $LINENO"; exit 1' ERR
echo "user-data start: $(date -Is)"

# ---- SSM Agent ----
snap install amazon-ssm-agent --classic
systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service
systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service

# ---- Base packages ----
apt-get update -y
export DEBIAN_FRONTEND=noninteractive
apt-get install -y less unzip realmd sssd-ad sssd-tools libnss-sss \
    libpam-sss adcli samba samba-common-bin samba-libs oddjob \
    oddjob-mkhomedir packagekit krb5-user nano vim nfs-common \
    winbind libpam-winbind libnss-winbind stunnel4

# ---- EFS utils ----
cd /tmp
git clone https://github.com/mamonaco1973/amazon-efs-utils.git
cd amazon-efs-utils
sudo dpkg -i amazon-efs-utils*.deb
which mount.efs

# ---- AWS CLI v2 ----
cd /tmp
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm -f -r awscliv2.zip aws

# ---- EFS mounts ----
mkdir -p /efs
echo "${efs_mnt_server}:/ /efs   efs   _netdev,tls  0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
mount /efs

mkdir -p /efs/home
mkdir -p /efs/data

# Shared extension cache — lets every node reuse one download of a
# VSIX instead of each user re-fetching it into their own home dir.
mkdir -p /efs/extensions

echo "${efs_mnt_server}:/home /home  efs   _netdev,tls  0 0" | sudo tee -a /etc/fstab
systemctl daemon-reload
mount /home
df -H

# ---- AD join ----
secretValue=$(aws secretsmanager get-secret-value --secret-id ${admin_secret} \
    --query SecretString --output text)
admin_password=$(echo $secretValue | jq -r '.password')
admin_username=$(echo $secretValue | jq -r '.username' | sed 's/.*\\//')

echo -e "$admin_password" | sudo /usr/sbin/realm join --membership-software=samba \
    -U "$admin_username" ${domain_fqdn} --verbose 

# ---- SSH + SSSD tweaks ----
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' \
    /etc/ssh/sshd_config.d/60-cloudimg-settings.conf

# Give the local ubuntu account the AD admin password. No EC2 key pair is
# attached to this host, so without this the only way in is an SSM session,
# and ubuntu cannot log in interactively at all. Reuses the admin secret
# rather than minting another one — lab convenience, not a pattern to copy.
echo "ubuntu:$admin_password" | sudo chpasswd

sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/g' \
    /etc/sssd/sssd.conf
sudo sed -i 's/ldap_id_mapping = True/ldap_id_mapping = False/g' \
    /etc/sssd/sssd.conf
sudo sed -i 's|fallback_homedir = /home/%u@%d|fallback_homedir = /home/%u|' \
    /etc/sssd/sssd.conf

touch /etc/skel/.Xauthority
chmod 600 /etc/skel/.Xauthority

sudo pam-auth-update --enable mkhomedir
sudo systemctl restart ssh

# ---- Samba ----
sudo systemctl stop sssd

cat <<EOT > /tmp/smb.conf
[global]
workgroup = ${netbios}
security = ads

# Performance tuning
strict sync = no
sync always = no
aio read size = 1
aio write size = 1
use sendfile = yes

passdb backend = tdbsam

# Printing subsystem (legacy, usually unused in cloud)
printing = cups
printcap name = cups
load printers = yes
cups options = raw

kerberos method = secrets and keytab

# Default user template
template homedir = /home/%U
template shell = /bin/bash
#netbios 

# File creation masks
create mask = 0770
force create mode = 0770
directory mask = 0770
force group = ${force_group}

realm = ${realm}

# ID mapping configuration
idmap config ${realm} : backend = sss
idmap config ${realm} : range = 10000-1999999999
idmap config * : backend = tdb
idmap config * : range = 1-9999

# Winbind options
min domain uid = 0
winbind use default domain = yes
winbind normalize names = yes
winbind refresh tickets = yes
winbind offline logon = yes
winbind enum groups = no
winbind enum users = no
winbind cache time = 30
idmap cache time = 60

[homes]
comment = Home Directories
browseable = No
read only = No
inherit acls = Yes

[efs]
comment = Mounted EFS area
path = /efs
read only = no
guest ok = no
EOT

sudo cp /tmp/smb.conf /etc/samba/smb.conf
sudo rm /tmp/smb.conf

head /etc/hostname -c 15 > /tmp/netbios-name
value=$(</tmp/netbios-name)
value=$(echo "$value" | tr -d '-' | tr '[:lower:]' '[:upper:]')
export netbios="$${value^^}"
sudo sed -i "s/#netbios/netbios name=$netbios/g" /etc/samba/smb.conf

cat <<EOT > /tmp/nsswitch.conf
passwd:     files sss winbind
group:      files sss winbind
automount:  files sss winbind
shadow:     files sss winbind
hosts:      files dns myhostname
bootparams: nisplus [NOTFOUND=return] files
ethers:     files
netmasks:   files
networks:   files
protocols:  files
rpc:        files
services:   files sss
netgroup:   files sss
publickey:  nisplus
aliases:    files nisplus
EOT

sudo cp /tmp/nsswitch.conf /etc/nsswitch.conf
sudo rm /tmp/nsswitch.conf

sudo systemctl restart winbind smb nmb sssd

# ---- Sudo + permissions ----
echo "%linux-admins ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/10-linux-admins

sudo sed -i 's/^\(\s*HOME_MODE\s*\)[0-9]\+/\10700/' /etc/login.defs

ln -s /efs /etc/skel/efs
su -c "exit" rpatel
su -c "exit" jsmith
su -c "exit" akumar
su -c "exit" edavis

chgrp ${force_group} /efs
chgrp ${force_group} /efs/data
chgrp ${force_group} /efs/extensions

chmod 2770 /efs
chmod 2775 /efs/extensions
chmod 2770 /efs/data
chmod 700 /home/*

cd /efs
git clone https://github.com/mamonaco1973/aws-vscode-shinyproxy.git
chmod -R 775 aws-vscode-shinyproxy
chgrp -R ${force_group} aws-vscode-shinyproxy

realm list
