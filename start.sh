#!/bin/bash
set -e

# set defaults
default_hostname="$(hostname)"
default_domain="netson.local"
default_puppetmaster="foreman.netson.nl"
tmp="/root/"

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

    # ask whether to add puppetlabs repositories
    while true; do
        read -p " do you wish to add the latest puppet repositories from puppetlabs? [y/n]: " yn
        case $yn in
            [Yy]* ) include_puppet_repo=1
                    puppet_deb="puppetlabs-release-"$ubuntu_version".deb"
                    break;;
            [Nn]* ) include_puppet_repo=0
                    puppet_deb=""
                    puppetmaster="puppet"
                    break;;
            * ) echo " please answer [y]es or [n]o.";;
        esac
    done

    if [[ include_puppet_repo ]] ; then
        # ask whether to setup puppet agent or not
        while true; do
            read -p " do you wish to setup the puppet agent? [y/n]: " yn
            case $yn in
                [Yy]* ) setup_agent=1
                        read -ep " please enter your puppet master: " -i "$default_puppetmaster" puppetmaster
                        break;;
                [Nn]* ) setup_agent=0
                        puppetmaster="puppet"
                        break;;
                * ) echo " please answer [y]es or [n]o.";;
            esac
        done
    fi

fi

# print status message
echo " preparing your server; this may take a few minutes ..."

# set fqdn
fqdn="$hostname.$domain"

# update hostname
echo "$hostname" > /etc/hostname
sed -i "s@ubuntu.ubuntu@$fqdn@g" /etc/hosts
sed -i "s@ubuntu@$hostname@g" /etc/hosts
hostname "$hostname"

# update repos
apt-get -y update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove
apt-get -y purge

# install puppet
if [[ include_puppet_repo -eq 1 ]]; then
    # install puppet repo
    wget https://apt.puppetlabs.com/$puppet_deb -O $tmp/$puppet_deb
    dpkg -i $tmp/$puppet_deb
    apt-get -y update
    rm $tmp/$puppet_deb
    
    # check to install puppet agent
    if [[ setup_agent -eq 1 ]] ; then
        # install puppet
        apt-get -y install puppet

        # set puppet master settings
        sed -i "s@\[master\]@\
# configure puppet master\n\
server=$puppetmaster\n\
report=true\n\
pluginsync=true\n\
\n\
\[master\]@g" /etc/puppet/puppet.conf

        # remove the deprecated template dir directive from the puppet.conf file
        sed -i "/^templatedir=/d" /etc/puppet/puppet.conf

        # download the finish script if it doesn't yet exist
        if [[ ! -f $tmp/finish.sh ]]; then
            echo -n " downloading finish.sh: "
            cd $tmp
            download "https://raw.githubusercontent.com/netson/ubuntu-unattended/master/finish.sh"
        fi

        # set proper permissions on finish script
        chmod +x $tmp/finish.sh

        # connect to master and ensure puppet is always the latest version
        echo " connecting to puppet master to request new certificate"
        echo " please sign the certificate request on your puppet master ..."
        puppet agent --waitforcert 60 --test
        echo " once you've signed the certificate, please run finish.sh from your home directory"

    fi

fi

# remove myself to prevent any unintended changes at a later stage
rm $0

# finish
echo " DONE; rebooting ... "

# reboot
reboot
