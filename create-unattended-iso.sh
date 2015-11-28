#!/usr/bin/env bash

# file names & paths
tmp="/tmp"  # destination folder to store the final iso file
hostname="ubuntu"
dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

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

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED UBUNTU ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

# ask whether to include vmware tools or not
while true; do
    echo " which ubuntu edition would you like to remaster:"
    echo
    echo "  [1] Ubuntu 12.04.4 LTS Server amd64 - Precise Pangolin"
    echo "  [2] Ubuntu 14.04.3 LTS Server amd64 - Trusty Tahr"
    echo "  [3] Ubuntu 15.10 Server amd64       - Wily Werewolf"
    echo
    read -p " please enter your preference: [1|2|3]: " ubver
    case $ubver in
        [1]* )  download_file="ubuntu-12.04.4-server-amd64.iso"           # filename of the iso to be downloaded
                download_location="http://releases.ubuntu.com/12.04/"     # location of the file to be downloaded
                new_iso_name="ubuntu-12.04.4-server-amd64-unattended.iso" # filename of the new iso file to be created
                break;;
        [2]* )  download_file="ubuntu-14.04.3-server-amd64.iso"             # filename of the iso to be downloaded
                download_location="http://releases.ubuntu.com/14.04/"     # location of the file to be downloaded
                new_iso_name="ubuntu-14.04.3-server-amd64-unattended.iso"   # filename of the new iso file to be created
                break;;
        [3]* )  download_file="ubuntu-15.10-server-amd64.iso"
                download_location="http://releases.ubuntu.com/15.10/"
                new_iso_name="ubuntu-15.10-server-amd64-unattended.iso"
                break;;
        * ) echo " please answer [1] or [2] or [3]";;
    esac
done

if [ -f /etc/timezone ]; then
  timezone=`cat /etc/timezone`
elif [ -h /etc/localtime]; then
  timezone=`readlink /etc/localtime | sed "s/\/usr\/share\/zoneinfo\///"`
else
  checksum=`md5sum /etc/localtime | cut -d' ' -f1`
  timezone=`find /usr/share/zoneinfo/ -type f -exec md5sum {} \; | grep "^$checksum" | sed "s/.*\/usr\/share\/zoneinfo\///" | head -n 1`
fi

# ask the user questions about his/her preferences
read -ep " please enter your preferred timezone: " -i "${timezone}" timezone
read -ep " please enter your preferred username: " -i "netson" username
read -sp " please enter your preferred password: " password
printf "\n"
read -sp " confirm your preferred password: " password2
printf "\n"
read -ep " Make ISO bootable via USB: " -i "yes" bootable

# check if the passwords match to prevent headaches
if [[ "$password" != "$password2" ]]; then
    echo " your passwords do not match; please restart the script and try again"
    echo
    exit
fi

# download the ubunto iso
cd $tmp
if [[ ! -f $tmp/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location$download_file"
fi


seed_file="netson.seed"
if [ -e ${dir}/${seed_file} ]; then
    # use local seed file if exists
    echo "copy seed file cp ${dir}/${seed_file} ./${seed_file}"
    cp ${dir}/${seed_file} ./${seed_file}
else
    # download netson seed file
    if [[ ! -f $tmp/$seed_file ]]; then
        echo -h " downloading $seed_file: "
        download "https://github.com/geraldhansen/ubuntu-unattended/raw/master/$seed_file"
    fi
fi

if [ ${username} = "root" ]; then
    echo -e "set up root account"
    if [ -e ${dir}/root_account.seed ]; then 
        cat ${dir}/root_account.seed >> $seed_file
    else
        download "https://github.com/geraldhansen/ubuntu-unattended/raw/master/root_account.seed"
        cat root_account.seed >> $seed_file
    fi
else
    echo -e "set up user account"
    if [ -e ${dir}/user_account.seed ]; then 
        cat ${dir}/user_account.seed >> $seed_file
    else
        download "https://github.com/geraldhansen/ubuntu-unattended/raw/master/user_account.seed"
        cat user_account.seed >> $seed_file
    fi 
fi

# install required packages
echo " installing required packages"
if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
    (apt-get -y update > /dev/null 2>&1) &
    spinner $!
    (apt-get -y install whois genisoimage > /dev/null 2>&1) &
    spinner $!
fi
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    if [ $(program_is_installed "isohybrid") -eq 0 ]; then
        (apt-get -y install syslinux > /dev/null 2>&1) &
        spinner $!
    fi
fi


# create working folders
echo " remastering your iso file"
mkdir -p $tmp
mkdir -p $tmp/iso_org
mkdir -p $tmp/iso_new

# mount the image
if grep -qs $tmp/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop $tmp/$download_file $tmp/iso_org > /dev/null 2>&1)
fi

# copy the iso contents to the working directory
(cp -rT $tmp/iso_org $tmp/iso_new > /dev/null 2>&1) &
spinner $!

# set the language for the installation menu
cd $tmp/iso_new
echo en > $tmp/iso_new/isolinux/lang

# copy the netson seed file to the iso
cp -rT $tmp/$seed_file $tmp/iso_new/preseed/$seed_file

# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)

# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{pwhash}}@$pwhash@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{hostname}}@$hostname@g" $tmp/iso_new/preseed/$seed_file
sed -i "s@{{timezone}}@$timezone@g" $tmp/iso_new/preseed/$seed_file

# calculate checksum for seed file
seed_checksum=$(md5sum $tmp/iso_new/preseed/$seed_file)

# add the autoinstall option to the menu
sed -i "/label install/ilabel autoinstall\n\
  menu label ^Autoinstall NETSON Ubuntu Server\n\
  kernel /install/vmlinuz\n\
  append file=/cdrom/preseed/ubuntu-server.seed initrd=/install/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/netson.seed preseed/file/checksum=$seed_checksum --" $tmp/iso_new/isolinux/txt.cfg

# automate boot start, because prompt 0 and timeout 0 will not work together
sed -i 's/^timeout 0$/timeout 1/' $tmp/iso_new/isolinux/isolinux.cfg
sed -i '/set menu_color_highlight/ a set default=0' $tmp/iso_new/boot/grub/grub.cfg
sed -i '/set menu_color_highlight/ a set timeout=10' $tmp/iso_new/boot/grub/grub.cfg

echo " creating the remastered iso"
cd $tmp/iso_new
(mkisofs -D -r -V "NETSON_UBUNTU" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $tmp/$new_iso_name . > /dev/null 2>&1) &
spinner $!

# make iso bootable (for dd'ing to  USB stick)
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    isohybrid $tmp/$new_iso_name
fi

# cleanup
umount $tmp/iso_org
rm -rf $tmp/iso_new
rm -rf $tmp/iso_org
rm -f $tmp/$seed_file

# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: $tmp/$new_iso_name"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

# unset vars
unset username
unset password
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file
