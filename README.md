# rdmo_lxc_dev-setup

Creates an LXC-container with development deployment of RDMO inside.

## Assumptions & pre-requistites

+ Host system: Debian 9 (Stretch)
+ LXC is installed.
+ Masqueraded networking setup for LXC containers as specified below.
+ User has passwordless sudo capabilities on host.

### LXC networking (configuration on host)

/etc/defaut/lxc-net contains:
~~~
USE_LXC_BRIDGE="true"
LXC_BRIDGE="lxcbr0"
LXC_ADDR="10.0.3.1"
LXC_NETMASK="255.255.255.0"
LXC_NETWORK="10.0.3.0/24"
~~~

/etc/lxc/default.conf  contains:
~~~
lxc.network.type = veth
lxc.network.flags = up
lxc.network.link = lxcbr0
~~~

## Usage

1. Customize the variables that show up until [line 64](https://github.com/eawag-rdm/rdmo_lxc_dev-setup/blob/47dd9b27f01cda60fb20bc8ac6d282b66ee78d8d/mk_rdmo_lxc.sh#L64).
2. Run it.

## Expected result
+ You should be able to see RDMO at http://10.0.3.33:8000 in a browser on the host (or another IP if you chode so).
+ You can login as admin with the username and password configured in the script.
+ You can passwordless ssh into the container from the account on the host, which has the ssh-key-pair the public part of which you provided in the script-configuration.
+ You have passwordless sudo in the container.
+ You start hacking right away.

