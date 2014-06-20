#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="netson.local"
default_puppetmaster="foreman.netson.nl"
tmp="/home/netson/"

clear

# check for root privilege
if [ "$(id -u)" != "0" ]; then
   echo " this script must be run as root" 1>&2
   echo
   exit 1
fi

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# determine ubuntu version
ubuntu_version=$(lsb_release -cs)

# check for interactive shell
if ! grep -q "noninteractive" /proc/cmdline ; then
    stty sane

    # ask questions
    read -ep " please enter your preferred hostname: " -i "$default_hostname" hostname
    read -ep " please enter your preferred domain: " -i "$default_domain" domain

    # ask whether to setup puppet agent or not
    while true; do
        read -p " do you wish to install the latest puppet agent from the puppetlabs repositories? [y/n]: " yn
        case $yn in
            [Yy]* ) include_puppet=true
                    puppet_deb="puppetlabs-release-"$ubuntu_version".deb"
                    break;;
            [Nn]* ) include_puppet=false
                    puppet_deb=""
                    break;;
            * ) echo " please answer [y]es or [n]o.";;
        esac
    done

fi

# print status message
echo " preparing your server ..."

# set fqdn
fqdn="$hostname.$domain"

# update hostname
echo "$hostname" > /etc/hostname
sed -i "s@ubuntu.ubuntu@$fqdn@g" /etc/hosts
sed -i "s@ubuntu@$hostname@g" /etc/hosts
hostname "$hostname"

# update repos
apt-get -y update > /dev/null 2>&1
apt-get -y upgrade > /dev/null 2>&1

# install puppet
if [[ include_puppet ]]; then
    # install puppet
    wget https://apt.puppetlabs.com/$puppet_deb -O $tmp/$puppet_deb > /dev/null 2>&1
    dpkg -i $tmp/$puppet_deb > /dev/null 2>&1
    apt-get -y update > /dev/null 2>&1
    apt-get -y install puppet > /dev/null 2>&1

    # set puppet master settings
    sed -i "s@\[master\]@\
# configure puppet master\n\
server=$puppetmaster\n\
report=true\n\
pluginsync=true\n\
\n\
\[master\]@g" /etc/puppet/puppet.conf

    # download the finish script if it doesn't yet exist
    if [[ ! -f $tmp/finish.sh ]]; then
        echo -n " downloading finish.sh: "
        cd $tmp
        "https://github.com/netson/ubuntu-unattended/raw/master/finish.sh"
    fi
    
    # set proper permissions on finish script
    chmod +x $tmp/finish.sh

    # connect to master and ensure puppet is always the latest version
    echo " connecting to puppet master to request new certificate"
    echo " please sign the certificate request on your puppet master ..."
    puppet agent --waitforcert 60 --test
    echo " once you've signed the certificate, please run finish.sh from your home directory"

fi

# remove myself to prevent any unintended changes at a later stage
rm $0

# finish
echo " DONE!"