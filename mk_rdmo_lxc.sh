#!/bin/bash

set -e

cat <<EOF

HVW-2017-08-10 @ Eawag
This script creates a privileged LXC container and installs RDMO for development
inside. It assumes that the executing user has password-less sudo capabilities.

Prerequisites for networking (Host: Debian Stretch):

/etc/defaut/lxc-net contains:

USE_LXC_BRIDGE="true"
LXC_BRIDGE="lxcbr0"
LXC_ADDR="10.0.3.1"
LXC_NETMASK="255.255.255.0"
LXC_NETWORK="10.0.3.0/24"
LXC_DHCP_RANGE="10.0.3.2,10.0.3.254"
LXC_DHCP_MAX="253"
LXC_DHCP_CONFILE=""
LXC_DOMAIN=""

/etc/lxc/default.conf  contains:

lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = lxcbr0


EOF

# Adapt any settings in this section, if necessary #############################

# Which app to install.
APP="CKAN"
#APP="RDMO"

# Arbitrary name for container
CONTAINERNAME=ckan
#CONTAINERNAME=rdmo

# Has to be in 10.0.3.0/24
CONTAINER_IP=10.0.3.33

# Username in the container (developer)
USER=hvwaldow
USER_EMAIL=harald@vonwaldow.ch
# initial superuser password for the app. You might want to change that
# even for the development installation.
DB_PWD=$USER

# Public ssh-key of the developer on the host (better don't use mine :).
# This is used to enable passwordless login to container
SSH_PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDBFTyAK5iF+rtEfnkThhyISsRZaRnVheTVoBS5P0ZEdNyOrIpi5XpT8xFsFYOLu+wI+wzDd9i7IR0FMgcYRN3e3igv4Rt9Ca8GgYsJ/Qtwwfy2mBywm7YLeP48iw20zlvAqx0vLOpS7KUBqxqnOMbETHfXbATCa8KLALlKiX8hyxl3ueobaYb9CNIUVG62jwsu7stqLDlLzz8DQOi9UyuSjLMmcZjefNSMKtFLGKB2OcK+Bg+zZf+LlAOFE6cg9QCwbyBObGVwkD7Ht+abCHBdbUpVgmW/3FhTc33nK+3fVcyfK//2op57SZlRXXr3Vr8W//FN3jv76GDeBMnUzE/z hvwaldow@l1"

# Per default we assume that /etc/resolv.conf of the container
# should be the same as the one of the host. If that is not the case
# uncomment and modify below.

# RESOLV_CONF=$(cat <<EOF
# domain my.domain
# search search.domain.one. search.domain.two. another.search.domain.
# nameserver 8.8.8.8
# nameserver 8.8.8.8
# EOF


# This script works only with Debian and has been only tested for this
# release and architecture.
DISTRIBUTION=debian
RELEASE=stretch
ARCH=amd64

################################################################################

# Basic software
PACKAGES="openssh-server vim sudo curl git"

# Application specific settings
if [[ "$APP" == "CKAN" ]]; then
    PACKAGES_DEV="python-dev postgresql libpq-dev python-pip python-virtualenv"
    CKAN_VERSION="@ckan-2.6.3"

elif [[ "$APP" == "RDMO" ]]; then
    PACKAGES_DEV="build-essential libxml2-dev libxslt-dev zlib1g-dev python3-dev python3-pip python3-venv pandoc"
else
    echo "\"$APP\" is not a supported application."
    exit 1
fi

################################################################################

ROOTFS="/var/lib/lxc/$CONTAINERNAME/rootfs"

logdo() {
    echo -e "\n----------------------------------------------------------------------"
    echo -e $1
    echo -e "----------------------------------------------------------------------\n"
}

create_container() {
    logdo "Creating container:\n\tName: $CONTAINERNAME\n\tDistribution: $DISTRIBUTION\n\tRelease: $RELEASE\n\tArch: $ARCH"
    sudo lxc-create -n $CONTAINERNAME -t download -- --dist $DISTRIBUTION\
    	 --release $RELEASE --arch $ARCH
    logdo "Container rdmo created."
}

network_setup() {
    logdo "Configuring container networking"
    echo -e "\t configuring /var/lib/lxc/$CONTAINERNAME/config"
    sudo sh -c "echo \"lxc.network.ipv4 = ${CONTAINER_IP}/24\" \
     >> /var/lib/lxc/$CONTAINERNAME/config"
    sudo sh -c "echo \"lxc.network.ipv4.gateway = auto\" \
     >> /var/lib/lxc/$CONTAINERNAME/config"

    # Replace "dhcp" in default /etc/network/interfaces with "manual"
    echo -e "\t writing >$ROOTFS/etc/network/interfaces"
    interfaces=$(cat <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual
EOF
)
    sudo sh -c "echo \"$interfaces\" >$ROOTFS/etc/network/interfaces"
    echo -e "\t configuring $ROOTFS/etc/hosts"
    # add $CONTAINERNAME to 127.0.0.1 in /etc/hosts
    sudo sed  -i '/127.0.0.1[ \t]\{1,\}localhost/ s/$/ '"$CONTAINERNAME"'/'\
	 $ROOTFS/etc/hosts

    echo -e "\t configuring $ROOTFS/etc/resolv.conf"
    if [ -z $RESOV_CONF ]
    then
	sudo cp /etc/resolv.conf $ROOTFS/etc/resolv.conf
    else
	sudo sh -c "echo \"$RESOLV_CONF\" >$ROOTFS/etc/resolv.conf"
    fi
    logdo "Container networking configured"
}

create_user() {
    logdo "Creating user $USER."
    setup_user=$(cat <<EOF
mkdir \$HOME/.ssh
chmod 700 \$HOME/.ssh
echo $SSH_PUBKEY >\$HOME/.ssh/authorized_keys
chmod 600 \$HOME/.ssh/authorized_keys
EOF
	      )
    sudo lxc-start -n $CONTAINERNAME
    sudo lxc-attach -n $CONTAINERNAME -- useradd -m -s /bin/bash $USER
    sudo lxc-attach -n $CONTAINERNAME -- usermod -aG sudo $USER
    sudo lxc-attach -n $CONTAINERNAME -- su - -c "$setup_user" $USER
    # Remove host-key from known_hosts; necessary for destroy-create cycles
    ssh-keygen -f "$HOME/.ssh/known_hosts" -R $CONTAINER_IP
    sudo lxc-stop -n $CONTAINERNAME
    logdo "User $USER created."
}

setup_sudo() {
    logdo "Setup sudo."
    sudo chmod 640 $ROOTFS/etc/sudoers
    sudo sed -i \
	 's/%sudo[\t ]\{1,\}ALL=(ALL:ALL) ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL/' \
    $ROOTFS/etc/sudoers
    sudo chmod 440 $ROOTFS/etc/sudoers
    logdo "sudo is set up."
}

install_packages() {
    logdo "Installing base packages."
    base_packages_install=$(cat <<EOF
#!/bin/bash
apt-get update
apt-get dist-upgrade -y
apt-get install $PACKAGES -y
EOF
)

    dev_packages_install=$( cat <<EOF
#!/bin/bash
apt-get install $PACKAGES_DEV -y
EOF
)
    sudo sh -c "echo  \"$base_packages_install\" >$ROOTFS/root/base_packages.sh"
    sudo sh -c "echo  \"$dev_packages_install\" >$ROOTFS/root/dev_packages.sh"
    sudo chmod u+x $ROOTFS/root/base_packages.sh
    sudo chmod u+x $ROOTFS/root/dev_packages.sh

    sudo lxc-start -n $CONTAINERNAME
    sudo lxc-attach -n $CONTAINERNAME -- /root/base_packages.sh
    sudo lxc-attach -n $CONTAINERNAME -- /root/dev_packages.sh
    sudo lxc-stop -n $CONTAINERNAME
    logdo "Base packages installed."
}

setup_ckan() {
    logdo "Install CKAN dev-environment"
    sudo lxc-start -n $CONTAINERNAME
    ssh $USER@$CONTAINER_IP \
        "mkdir -p ~/ckan/lib;
         sudo ln -s ~/ckan/lib /usr/lib/ckan;
         mkdir -p ~/ckan/etc;
         sudo ln -s ~/ckan/etc /etc/ckan;
         sudo mkdir -p /usr/lib/ckan/default;
         sudo chown `whoami` /usr/lib/ckan/default;
         virtualenv /usr/lib/ckan/default;"
    VENVPY="/usr/lib/ckan/default/bin/python"
    VENVPIP="/usr/lib/ckan/default/bin/pip"
    ssh $USER@$CONTAINER_IP $VENVPIP "install -e 'git+https://github.com/ckan/ckan.git${CKAN_VERSION}#egg=ckan'"
    ssh $USER@$CONTAINER_IP $VENVPIP "install -r /usr/lib/ckan/default/src/ckan/requirements.txt"
    sudo lxc-stop -n $CONTAINERNAME
    logdo "Done installing CKAN dev-environment"
}

setup_rdmo() {
    logdo "Install RDMO requirements."
    setup_rdmo=$(cat <<EOF
git clone https://github.com/rdmorganiser/rdmo.git
cd rdmo
python3 -m venv env
mkdir components_root
curl -L https://github.com/rdmorganiser/rdmo-components/archive/master.tar.gz\
 | tar xvz -C components_root --strip-components=1\
 rdmo-components-master/bower_components
./env/bin/pip3 install wheel
./env/bin/pip3 install -r requirements/base.txt
cat rdmo/settings/sample.local.py |sed -r\
 's/(ALLOWED_HOSTS.*)\['\''localhost'\''\]/\1['\''localhost'\'', '\''$CONTAINER_IP'\'']/' \
 >rdmo/settings/local.py
EOF
)
    sudo bash -c "echo \"$setup_rdmo\" >$ROOTFS/home/$USER/setup_rdmo.sh"
    sudo lxc-start -n $CONTAINERNAME
    sudo lxc-attach -n $CONTAINERNAME -- \
    	 chown $USER:$USER /home/$USER/setup_rdmo.sh
    sudo lxc-attach -n $CONTAINERNAME -- \
         chmod u+x /home/$USER/setup_rdmo.sh
    sudo lxc-attach -n $CONTAINERNAME -- \
    	 su - -c /home/$USER/setup_rdmo.sh  $USER
    sudo lxc-stop -n $CONTAINERNAME
    logdo "RDMO requirements installed."
}

init_rdmo() {
    logdo "Initializing RDMO."
    initcmd=$(cat <<EOF
cd /home/$USER/rdmo; \
./env/bin/python3 manage.py migrate; \
./env/bin/python3 manage.py create-groups; \
echo "from django.contrib.auth.models import User; User.objects.create_superuser('$USER', '$USER_EMAIL', '$DB_PWD')" | ./env/bin/python3 manage.py shell
EOF
)
    sudo lxc-start -n $CONTAINERNAME
    sudo lxc-attach -n $CONTAINERNAME -- \
	 su - -c  "$initcmd" $USER
    sudo lxc-stop -n $CONTAINERNAME
    logdo "RDMO initialized."
}

run_server() {
    logdo "Running development server at $CONTAINER_IP:8000"
    rdmobase="/home/$USER/rdmo"
    sudo lxc-start -n $CONTAINERNAME
    sudo lxc-attach -n $CONTAINERNAME -- \
	 su - -c "$rdmobase/env/bin/python3 $rdmobase/manage.py runserver 0.0.0.0:8000" $USER
}

# create_container
# network_setup
# create_user
# install_packages
# setup_sudo
# setup_ckan

# next: postgresql

# setup_rdmo
# init_rdmo		 
# run_server
