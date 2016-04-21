#!/bin/bash
set -e

# check for root privilege
if [ "$(id -u)" != "0" ]; then
   echo " this script must be run as root" 1>&2
   echo
   exit 1
fi

echo " finishing your puppet installation ... "

# run puppet config
sed -i "s@START=no@START=yes@g" /etc/default/puppet
puppet resource package puppet ensure=latest > /dev/null
puppet resource service puppet ensure=running enable=true > /dev/null
puppet agent --enable > /dev/null
puppet agent
# puppet agent --test

# remove myself to prevent any unintended changes at a later stage
rm $0

# finish
echo " DONE!"