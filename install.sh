#!/bin/sh
# Arch Bootstrap

### OPTIONS AND VARIABLES ###

while getopts ":b:h" o; do case "${o}" in
    h) printf "Optional arguments for custom use:\\n  -b: Dotfiles branch (master is assumed otherwise)\\n  -h: Show this message\\n" && exit ;;
    b) repobranch=${OPTARG} ;;
    *) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
esac done

# DEFAULTS:
dotfilesrepo="https://github.com/BeaudanBrown/dotarch.git"
dotfilesrepossh="git@github.com:BeaudanBrown/dotarch.git"
progsfile="https://raw.githubusercontent.com/BeaudanBrown/archbootstrap/master/progs.csv"
aurhelper="yay"
[ -z "$repobranch" ] && repobranch="master"

### FUNCTIONS ###

error() {
    clear; printf "ERROR:\\n%s\\n" "$1"; exit;
}

welcomemsg() {
    dialog --title "Welcome!" --msgbox "This script will install a fully featured arch linux bspwm system" 10 60
}

getuserandpass() {
    # Prompts user for new username an password.
    name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
    while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
        name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
    done
    pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
    pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    while ! [ "$pass1" = "$pass2" ]; do
        unset pass2
        pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
        pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
    done ;
}

usercheck() {
    ! (id -u "$name" >/dev/null) 2>&1 ||
    dialog --colors --title "WARNING!" --yes-label "CONTINUE" --no-label "No wait..." --yesno "The user \`$name\` already exists on this system. We can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nWe will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that we will change $name's password to the one you just gave." 14 70
}

preinstallmsg() {
    dialog --title "Let's get this party started!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit; }
}

adduserandpass() {
    # Adds user `$name` with password $pass1.
    dialog --infobox "Adding user \"$name\"..." 4 50
    useradd -m -g wheel -s /bin/bash "$name" >/dev/null 2>&1 ||
    usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home/"$name"
    echo "$name:$pass1" | chpasswd
    unset pass1 pass2 ;
}

refreshkeys() {
    dialog --infobox "Refreshing Arch Keyring..." 4 40
    pacman --noconfirm -Sy archlinux-keyring >/dev/null 2>&1
}

newperms() { # Set special sudoers settings for install (or after).
    sed -i "/#LARBS/d" /etc/sudoers
    echo "$* #LARBS" >> /etc/sudoers ;
}

manualinstall() { # Installs $1 manually if not installed. Used only for AUR helper here.
    [ -f "/usr/bin/$1" ] || (
    dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
    cd /tmp || exit
    rm -rf /tmp/"$1"*
    curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
    sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
    cd "$1" &&
    sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
    cd /tmp || return) ;
}

maininstall() { # Installs all needed programs from main repo.
    dialog --title "Arch bspwm Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
    pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

gitmakeinstall() {
    dir=$(mktemp -d)
    dialog --title "Arch bspwm Installation" --infobox "Installing \`$(basename "$1")\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
    git clone --depth 1 "$1" "$dir" >/dev/null 2>&1
    cd "$dir" || exit
    make >/dev/null 2>&1
    make install >/dev/null 2>&1
    cd /tmp || return ;
}

aurinstall() {
    dialog --title "Arch bspwm Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
    echo "$aurinstalled" | grep "^$1$" >/dev/null 2>&1 && return
    sudo -u "$name" $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
    dialog --title "Arch bspwm Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
    command -v pip || pacman -S --noconfirm --needed python-pip >/dev/null 2>&1
    yes | pip install "$1"
}

installationloop() {
    ([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
    total=$(wc -l < /tmp/progs.csv)
    aurinstalled=$(pacman -Qm | awk '{print $1}')
    while IFS=, read -r tag program comment; do
        n=$((n+1))
        echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
        case "$tag" in
            "") maininstall "$program" "$comment" ;;
            "A") aurinstall "$program" "$comment" ;;
            "G") gitmakeinstall "$program" "$comment" ;;
            "P") pipinstall "$program" "$comment" ;;
        esac
    done < /tmp/progs.csv ;
}

putgitrepo() { # Downlods a gitrepo $1 and places the files in $2 only overwriting conflicts
    dialog --infobox "Downloading and installing config files..." 4 60
    [ -z "$3" ] && branch="master" || branch="$repobranch"
    dir=$2
    [ ! -d "$dir" ] && mkdir -p "$dir" && chown -R "$name:wheel" "$dir"
    sudo -u "$name" git clone --bare $1 $dir
    function dot {
       sudo -u "$name" git --git-dir=$dir --work-tree=/home/$name/ $@
    }

    dot checkout
    if [ $? != 0 ]; then
        # Backup conflicting dotfiles
        mkdir -p .config-backup
        dot checkout 2>&1 | egrep "\s+\." | awk {'print $1'} | xargs -I{} mv {} .config-backup/{}
    fi;
    dot checkout
    dot config status.showUntrackedFiles no
    dot remote set-url origin $dotfilesrepossh
}

serviceinit() {
    for service in "$@"; do
        dialog --infobox "Enabling \"$service\"..." 4 40
        systemctl enable "$service"
        systemctl start "$service"
    done ;
}

userserviceinit() {
    for service in "$@"; do
        dialog --infobox "Enabling \"$service\"..." 4 40
        systemctl --user enable "$service"
        systemctl --user start "$service"
    done ;
}

systembeepoff() {
    dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
    rmmod pcspkr
    echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;
}

resetpulse() {
    dialog --infobox "Reseting Pulseaudio..." 4 50
    killall pulseaudio
    sudo -n "$name" pulseaudio --start ;
}

finalize(){
    dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nTo run the new graphical environment, log out and log back in as your new user, then run the command \"startx\" to start the graphical environment (it will start automatically in tty1).\\n\\n.t Luke" 12 80
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Check if user is root on Arch distro. Install dialog.
pacman -Syu --noconfirm --needed dialog ||  error "Are you sure you're running this as the root user? Are you sure you're using an Arch-based distro? ;-) Are you sure you have an internet connection? Are you sure your Arch keyring is updated?"

# Welcome user.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

adduserandpass || error "Error adding username and/or password."

# Refresh Arch keyrings.
refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

dialog --title "Arch bspwm Installation" --infobox "Installing \`basedevel\` and \`git\` for installing other software." 5 70
pacman --noconfirm --needed -S base-devel git >/dev/null 2>&1
[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall $aurhelper || error "Failed to install AUR helper."

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

# Install the dotfiles in bare git folder
putgitrepo "$dotfilesrepo" "/home/$name/.config/dotsGit" "$repobranch"
rm -f "/home/$name/README.md" "/home/$name/LICENSE"

# Pulseaudio, if/when initially installed, often needs a restart to work immediately.
[ -f /usr/bin/pulseaudio ] && resetpulse

# Enable services here.
serviceinit NetworkManager cronie bluetooth-autoconnect

# Enable user services here.
userserviceinit pulseaudio-bluetooth-autoconnect

# Most important command! Get rid of the beep!
systembeepoff

# Change shell to zsh
chsh -s /usr/bin/zsh $name

# Set up node for nvim plugins
if [ -f /home/$name/.local/bin/tools/fnm ]; then
    sudo -u $name -- sh -c "
        export FNM_DIR='/home/$name/.config/fnm/';
        /home/$name/.local/bin/tools/fnm install latest;
        /home/$name/.local/bin/tools/fnm ls | awk '/latest/ {print \$2}' | xargs -I {} fnm default {};
        /home/$name/.local/bin/tools/fnm use default
    "
fi

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL #LARBS
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/packer -Syu,/usr/bin/packer -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/rc-service NetworkManager restart,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm"

# Last message! Install complete!
finalize
clear
