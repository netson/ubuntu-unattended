#!/bin/bash
set -e

echo " finishing your puppet installation ... "

# run puppet config
# puppet resource package puppet ensure=latest > /dev/null
puppet resource service puppet ensure=running enable=true > /dev/null
puppet agent --enable > /dev/null
puppet agent
# puppet agent --test

# remove myself to prevent any unintended changes at a later stage
rm $0

# finish
echo " DONE!"