#!/bin/bash

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

/etc/lxc/default.conf  contains:

lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = lxcbr0


EOF

# Adapt any settings in this section, if necessary #############################

# Arbitrary name for container
CONTAINERNAME=rdmo

# Has to be in 10.0.3.0/24
CONTAINER_IP=10.0.3.33

# Username in the container (developer)
USER=hvw
USER_EMAIL=harald.vonwaldow@eawag.ch
# initial superuser password for the app. You might want to change that
# even for the development installation.
DB_PWD=$USER

# Public ssh-key of the developer on the host (better don't use mine :).
# This is used to enable passwordless login to container
SSH_PUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQChGPTwefwBQecG3FX8fbVkHjnwN5SGvFgrSZlNMUISvwEJVcEVMZd3IIr137RfpSICioDJfI5xcMnlg+xgoznd2TDDIHQYqlgNnNgiUiobdV6s0KHJQ7JolQvQT8Rqt37hvVS8TDPNUbjKG82BvmtYr2CpM9aWcQD7VaoMIl7r+eaiLNmFiX0Vi7tw+lX12agO87yxj6i8AmQAdfv+NVbxR4DxSu992zVOoRKCkf7pxNkXQTMsoDOJFvmgMJkPBMrJrVXNbJT/N4v4uXlGRo63TQuJUBv1Niwa155VqexEnwzE8wYx3beUQHegJmRFuc6nLqVNU2BOqOs5/C7aRcOuSrWy06Ww/Q8JYoO+5mrWmOPUmg6qMV00iKw6j+u5occPSkFh+ctel0GxHy4hwkItthvo+ix2EqyMv1gvN7zsxhLAbs2O4aHwl/7pEx5R8K0l4Mj+RWjeVdCo5nFxlY/8/7kqu4Kzp69D36sxzokFo7+Eoiw/kNwgL5flzoo2C12iMOWwkfJW72VVdFPypbJbb9pbGmjevOYboYb3CHdqs5aFCaat3cvMSR18aoChd3RgIT3jCWikF1v5Z68wBsto5ePDzwlezHJqQpFYbs3RXRvX3W0aKzjBYEPoE8m2motq+XyxkXBr7bleGh5VhGuI2EjI0jSl3KbzmEuyVa/aPQ== harald.vonwaldow@eawag.ch"

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

ROOTFS="/var/lib/lxc/$CONTAINERNAME/rootfs"

create_container() {
    sudo lxc-create -n $CONTAINERNAME -t download -- --dist $DISTRIBUTION\
	 --release $RELEASE --arch $ARCH
}

network_setup() {
    sudo sh -c "echo \"lxc.network.ipv4 = ${CONTAINER_IP}/24\" \
     >> /var/lib/lxc/$CONTAINERNAME/config"
    sudo sh -c "echo \"lxc.network.ipv4.gateway = auto\" \
     >> /var/lib/lxc/$CONTAINERNAME/config"

    # Replace "dhcp" in default /etc/network/interfaces with "manual"
    interfaces=$(cat <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual
EOF
)
    sudo sh -c "echo \"$interfaces\" >$ROOTFS/etc/network/interfaces"

    # add $CONTAINERNAME to 127.0.0.1 in /etc/hosts
    sudo sed  -i '/127.0.0.1[ \t]\{1,\}localhost/ s/$/ '"$CONTAINERNAME"'/'\
	 $ROOTFS/etc/hosts

    if [ -z $RESOV_CONF ]
    then
	sudo cp /etc/resolv.conf $ROOTFS/etc/resolv.conf
    else
	sudo sh -c "echo \"$RESOLV_CONF\" >$ROOTFS/etc/resolv.conf"
    fi
}

install_packages() {
    base_packages_install=$(cat <<EOF
#!/bin/bash
apt-get update
apt-get dist-upgrade -y
apt-get install openssh-server vim sudo curl git -y
EOF
)

    dev_packages_install=$( cat <<EOF
#!/bin/bash
apt-get install build-essential libxml2-dev libxslt-dev zlib1g-dev -y
apt-get install python3-dev python3-pip python3-venv git pandoc -y
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
}

create_user() {
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
    sudo lxc-stop -n $CONTAINERNAME

}

setup_sudo() {
    sudo chmod 640 $ROOTFS/etc/sudoers
    sudo sed -i \
	 's/%sudo[\t ]\{1,\}ALL=(ALL:ALL) ALL/%sudo   ALL=(ALL:ALL) NOPASSWD: ALL/' \
    $ROOTFS/etc/sudoers
    sudo chmod 440 $ROOTFS/etc/sudoers
}

setup_rdmo() {
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
}

init_rdmo() {
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

}

run_server() {
    rdmobase="/home/$USER/rdmo"
    sudo lxc-start -n $CONTAINERNAME
    sudo lxc-attach -n $CONTAINERNAME -- \
	 su - -c "$rdmobase/env/bin/python3 $rdmobase/manage.py runserver 0.0.0.0:8000" $USER
}

create_container
network_setup
install_packages
create_user
setup_sudo
setup_rdmo
init_rdmo		 
run_server
