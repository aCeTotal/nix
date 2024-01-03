#!/usr/bin/env -S bash -e

# Fixing annoying issue that breaks GitHub Actions
# shellcheck disable=SC2001

# Cleaning the TTY.
clear

# Cosmetics (colours for text).
BOLD='\e[1m'
BRED='\e[91m'
BBLUE='\e[34m'  
BGREEN='\e[92m'
BYELLOW='\e[93m'
RESET='\e[0m'

# Pretty print (function).
info_print () {
    echo -e "${BOLD}${BGREEN}[ ${BYELLOW}•${BGREEN} ] $1${RESET}"
}

# Pretty print for input (function).
input_print () {
    echo -ne "${BOLD}${BYELLOW}[ ${BGREEN}•${BYELLOW} ] $1${RESET}"
}

# Alert user of bad input (function).
error_print () {
    echo -e "${BOLD}${BRED}[ ${BBLUE}•${BRED} ] $1${RESET}"
}

# Cloning the repo
sudo git clone https://github.com/aCeTotal/nix.git

# Microcode detector (function).
microcode_detector () {
    CPU=$(grep vendor_id /proc/cpuinfo)
    if [[ "$CPU" == *"AuthenticAMD"* ]]; then
        info_print "An AMD CPU has been detected, the AMD microcode will be installed."
        microcode="hardware.cpu.amd.updateMicrocode = true;"
    else
        info_print "An Intel CPU has been detected, the Intel microcode will be installed."
        microcode="hardware.cpu.intel.updateMicrocode = true;"
    fi
}

# User enters a hostname (function).
hostname_selector () {
    input_print "Please enter the hostname Eg. OfficePC: "
    read -r hostname
    if [[ -z "$hostname" ]]; then
        error_print "You need to enter a hostname in order to continue. Eg. OfficePC or HyprNix."
        return 1
    fi
    return 0
}

# Welcome screen.
echo -ne "${BOLD}${BYELLOW}
======================================================================

██╗  ██╗██╗   ██╗██████╗ ██████╗        █████╗ ██████╗  ██████╗██╗  ██╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗      ██╔══██╗██╔══██╗██╔════╝██║  ██║
███████║ ╚████╔╝ ██████╔╝██████╔╝█████╗███████║██████╔╝██║     ███████║
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗╚════╝██╔══██║██╔══██╗██║     ██╔══██║
██║  ██║   ██║   ██║     ██║  ██║      ██║  ██║██║  ██║╚██████╗██║  ██║
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝      ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
                                                                       
======================================================================
${RESET}"
info_print "Welcome to the installation of HyprNix! :)"

# Choosing the target for the installation.
info_print "Available disks for the installation:"
lsblk
PS3="Please select the number of the corresponding disk (e.g. 1): "
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
do
    DISK="$ENTRY"
    info_print "HyprNix will be installed on the following disk: $DISK"
    break
done

# User choses the hostname.
until hostname_selector; do : ; done


# Warn user about deletion of old partition scheme.
input_print "WARNING! This will wipe the current partition table on $DISK once installation starts. Do you agree [y/N]?: "
read -r disk_response
if ! [[ "${disk_response,,}" =~ ^(yes|y)$ ]]; then
    error_print "Quitting."
    exit
fi
info_print "Wiping $DISK."
sudo wipefs -af "$DISK"
sudo sgdisk -Zo "$DISK"

# Creating a new partition scheme.
info_print "Creating the partitions on $DISK."
sudo parted -s "$DISK" mklabel gpt
sudo parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
sudo parted -s "$DISK" set 1 esp on
sudo parted -s "$DISK" mkpart ROOT 513MiB 100%

ESP="/dev/disk/by-partlabel/ESP"
ROOT="/dev/disk/by-partlabel/ROOT"

# Formatting the ESP as FAT32.
info_print "Formatting the EFI Partition as FAT32."
sudo mkfs.fat -F 32 "$ESP"

# Mounting the root partition.
info_print "Mounting the root partititon"
sudo mkfs.btrfs -f "$ROOT"
sudo mkdir -p /mnt
sudo mount "$ROOT" /mnt

# Creating BTRFS subvolumes.
info_print "Creating BTRFS subvolumes."
subvols=(root home nix log)
for subvol in '' "${subvols[@]}"; do
    sudo btrfs su cr /mnt/@"$subvol"
done

mountpoints_creation () {
# Create mountpoints.
info_print "Creating mounting points"
  sudo umount -l /mnt
  sudo mkdir -p /mnt/home
  sudo mkdir -p /mnt/nix
  sudo mkdir -p /mnt/var/log
  sudo mkdir -p /mnt/boot
  return 0
}


mount_subvolumes () {
# Mount subvolumes.
info_print "Mounting the newly created subvolumes."
  sudo mount -o compress=zstd,subvol=@root "$ROOT" /mnt
  sudo mount -o compress=zstd,subvol=@home "$ROOT" /mnt/home
  sudo mount -o compress=zstd,noatime,subvol=@nix "$ROOT" /mnt/nix
  sudo mount -o compress=zstd,subvol=@log "$ROOT" /mnt/var/log
  sudo mount "$ESP" /mnt/boot/

  sudo nixos-generate-config --root /mnt
  return 0
}

create_mainconf () {
# Create Configuration.nix.
info_print "Creating the main configuration.nix"
sudo rm /mnt/etc/nixos/configuration.nix
cat << EOF | sudo tee -a /mnt/etc/nixos/configuration.nix

# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [   # Include the results of the hardware scan.
        ./hardware-configuration.nix
        # Include Home Manager
        ./home.nix
    ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

EOF
return 0
}

create_homeconf () {
# Create Configuration.nix.
info_print "Creating the home-manager config, home.nix"
sudo rm /mnt/etc/nixos/home.nix
cat << EOF | sudo tee -a /mnt/etc/nixos/home.nix

# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

{
  imports =
    [   # Include the results of the hardware scan.
        ./hardware-configuration.nix
        # Include Home Manager
        ./home.nix
    ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

EOF
return 0
}

mountpoints_creation

mount_subvolumes

create_mainconf

create_homeconf
