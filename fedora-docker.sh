#!/bin/bash

# Defines the variables needed for deployment with this script.
#
# <UDF name="hostname" label="The hostname for the new Linode.">
# <UDF name="fqdn" label="The new Linode's Fully Qualified Domain Name">
# <UDF name="sshport" label="Change the port that the SSH service runs on, security by obscurity, but mostly just to keep the logs clean">
# <UDF name="sudo_username" label="A username to create a user for sudo usage, non-root access">
# <UDF name="git_email" label="An email address for configuring git.">
# <UDF name="sudo_userpassword" label="Password for the user account for sudo usage, non-root access">
# <UDF name="sudo_userkey" label="SSH Public Key for account login, much more secure than password login">

# This sets the variable $IPADDR to the IPv4 address the new Linode receives.
IPADDR=$(hostname -I | cut -f1 -d' ')

# This sets the variable $IPADDR6 to the IPv6 address the new Linode receives.
IPADDR6=$(hostname -I | cut -f2 -d' ')

# This updates the system to the latest updates using yum
yum update -y -q
yum install deltarpm net-tools git tmux -y -q

# This section sets the hostname on the account
hostnamectl set-hostname $FQDN

# This section updates the /etc/hosts file
echo $IPADDR $FQDN $HOSTNAME >> /etc/hosts
echo $IPADDR6 $FQDN $HOSTNAME >> /etc/hosts

# Configure a disk image for docker and home folder
DUUID=$(lsblk -no UUID /dev/xvdc)
HUUID=$(lsblk -no UUID /dev/xvdd)
FSTAB="UUID=$HUUID /home ext4 defaults 0 0\nUUID=$DUUID /var/lib/docker ext4 defaults 1 2"
awk -v FSTAB="$FSTAB" '/xvdb/ { print; print FSTAB; next }1' /etc/fstab > /etc/fstab_new
mv /etc/fstab /etc/fstab_bkp
mv /etc/fstab_new /etc/fstab
mount /dev/xvdc
mount /dev/xvdd

# This section adds the new user for sudo usage
useradd $SUDO_USERNAME
echo "$SUDO_USERNAME:$SUDO_USERPASSWORD" | chpasswd
usermod -a -G wheel $SUDO_USERNAME

# This section adds the user's public key to the server and configures the files/folders
mkdir -p /home/$SUDO_USERNAME/.ssh
echo "$SUDO_USERKEY" >> /home/$SUDO_USERNAME/.ssh/authorized_keys
chown -R $SUDO_USERNAME:$SUDO_USERNAME /home/$SUDO_USERNAME/.ssh
chmod go-w /root/
chmod go-w /home/$SUDO_USERNAME/
chmod 700 /home/$SUDO_USERNAME/.ssh
chmod 600 /home/$SUDO_USERNAME/.ssh/authorized_keys

# This section secures the SSH daemon
sed -i 's/#Port 22/Port '$SSHPORT'/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
echo "AllowGroups wheel" >> /etc/ssh/sshd_config
systemctl reload sshd

# This section sets up the basic firewall and enables it.
cp /usr/lib/firewalld/services/ssh.xml /etc/firewalld/services/ssh.xml
sed -i 's#<port protocol="tcp" port="22"/>#<port protocol="tcp" port="'$SSHPORT'"/>#' /etc/firewalld/services/ssh.xml
systemctl start firewalld
systemctl enable firewalld
firewall-cmd --zone=public --add-interface=eth0 --permanent
firewall-cmd --zone=public --add-service=ssh --permanent
firewall-cmd --reload

# Add a few useful aliases to .bashrc
echo "alias update='sudo yum update'" >> /home/$SUDO_USERNAME/.bashrc
echo "alias install='sudo yum install'" >> /home/$SUDO_USERNAME/.bashrc
echo "alias free='free -m'" >> /home/$SUDO_USERNAME/.bashrc
echo "alias firewall-cmd='sudo firewall-cmd'" >> /home/$SUDO_USERNAME/.bashrc
echo "alias df='sudo df -h'" >> /home/$SUDO_USERNAME/.bashrc

# Basic git configuration
git config --global user.email "$GIT_EMAIL"
git config --global user.name "$SUDO_USERNAME"
mv ~/.gitconfig /home/$SUDO_USERNAME/.gitconfig
chown $SUDO_USERNAME:$SUDO_USERNAME /home/$SUDO_USERNAME/.gitconfig
chmod 664 /home/$SUDO_USERNAME/.gitconfig

# Install docker-io from updates-testing due to latest version differences
# Add the new user to the docker group
yum install docker-io --enablerepo=updates-testing -y -q
sudo gpasswd -a $SUDO_USERNAME docker

# Start Docker and Enable for start on reboot
systemctl start docker
systemctl enable docker

# Reboot the server, ready to go
shutdown -r now
