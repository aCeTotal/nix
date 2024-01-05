#!/usr/bin/env -S bash -e

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
    echo -e "${BOLD}${BGREEN}[ ${BBLUE}•${BYELLOW} ] $1${RESET}"
}

# Pretty print for input (function).
input_print () {
    echo -ne "${BOLD}${BYELLOW}[ ${BGREEN}•${BYELLOW} ] $1${RESET}"
}

# Alert user of bad input (function).
error_print () {
    echo -e "${BOLD}${BRED}[ ${BBLUE}•${BRED} ] $1${RESET}"
}

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
    echo
    input_print "Please enter the hostname Eg. OfficePC: "
    read -r hostname
    if [[ -z "$hostname" ]]; then
        error_print "You need to enter a hostname in order to continue. Eg. OfficePC, HyprNix ect."
        return 1
    fi

    return 0
}

# User enters a username (function).
username_selector () {
    echo
    input_print "Please enter the name of your user: "
    read -r username
    if [[ -z "$username" ]]; then
        error_print "You need to enter a username in order to continue!"
        return 1
    fi
    echo
    info_print "Oh! Hi, $username! Welcome to the world of NixOS!"
    sleep 4
    echo
    info_print "Let's continue :)"
    sleep 2

    return 0
}

# Selecting Locale to use alongside the US-Locale. .
locale_selector () {
    echo
    echo
    echo
    info_print "Select an extra locale for Time, Measurement, Numeric ect. that will be used alongside the en_US locale:"
    echo
    info_print "1) English all the way!"
    info_print "2) Norwegian"
    info_print "3) Swedish"
    info_print "4) Danish"
    info_print "5) German"
    info_print "6) Spanish"
    echo
    input_print "Please select the number of the corresponding locale (e.g. 1): " 
    read -r xtra_locale_choice
    case $xtra_locale_choice in
        1 ) xtra_locale="en_US.UTF-8"
            return 0;;
        2 ) xtra_locale="nb_NO.UTF-8"
            return 0;;
        3 ) xtra_locale="sv_SE.UTF-8"
            return 0;;
        4 ) xtra_locale="da_DK.UTF-8"
            return 0;;
        5 ) xtra_locale="de_DE.UTF-8"
            return 0;;
        6 ) xtra_locale="es_ES.UTF-8"
            return 0;;
        * ) error_print "You did not enter a valid selection, please try again."
            return 1
    esac

}

# Selecting Locale to use alongside the US-Locale. .
keyboard_layout () {
  echo
  echo
  echo
    info_print "Select your keyboard layout:"
    echo
    info_print "1) English"
    info_print "2) Norwegian"
    info_print "3) Swedish"
    info_print "4) Danish"
    info_print "5) German"
    info_print "6) Spanish"
    echo
    input_print "Please select the number of the corresponding keyboard layout (e.g. 1): " 
    read -r keyboard_layout_choice
    case $keyboard_layout_choice in
        1 ) keyboard_layout="us"
            return 0;;
        2 ) keyboard_layout="no"
            return 0;;
        3 ) keyboard_layout="se"
            return 0;;
        4 ) keyboard_layout="dk"
            return 0;;
        5 ) keyboard_layout="de"
            return 0;;
        6 ) keyboard_layout="es"
            return 0;;
        * ) error_print "You did not enter a valid selection, please try again."
            return 1
    esac

}

# Welcome screen.
echo -ne "${BOLD}${BGREEN}
=========================================================

██╗  ██╗██╗   ██╗██████╗ ██████╗ ███╗   ██╗██╗██╗  ██╗
██║  ██║╚██╗ ██╔╝██╔══██╗██╔══██╗████╗  ██║██║╚██╗██╔╝
███████║ ╚████╔╝ ██████╔╝██████╔╝██╔██╗ ██║██║ ╚███╔╝ 
██╔══██║  ╚██╔╝  ██╔═══╝ ██╔══██╗██║╚██╗██║██║ ██╔██╗ 
██║  ██║   ██║   ██║     ██║  ██║██║ ╚████║██║██╔╝ ██╗
╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝
                                                      
=========================================================
${RESET}"
info_print "Welcome to the installation of HyprNix! :)"
echo

# Choosing the target for the installation.
info_print "Available disks for the installation:"
echo
lsblk
echo
PS3="Please select the number of the corresponding disk (e.g. 1): "
echo
select ENTRY in $(lsblk -dpnoNAME|grep -P "/dev/sd|nvme|vd");
do
    DISK="$ENTRY"
    echo
    info_print "HyprNix will be installed on the following disk: $DISK"
    break
done

# Warn user about deletion of old partition scheme.
echo
input_print "WARNING! This WILL wipe the current partition table on $DISK. Do you agree [y/N]?: "
read -r disk_response
if ! [[ "${disk_response,,}" =~ ^(yes|y)$ ]]; then
    error_print "Quitting."
    exit
fi
echo
info_print "Wiping $DISK."
sudo wipefs -af "$DISK" &>/dev/null
sudo sgdisk -Zo "$DISK" &>/dev/null

# User choses the hostname.
until hostname_selector; do : ; done

# User choses the hostname.
until username_selector; do : ; done

# User choses if he wants an xtra locale alongside en_US.
until locale_selector; do : ; done

# User choses if he wants an xtra locale alongside en_US.
until keyboard_layout; do : ; done

# Creating a new partition scheme.
echo
info_print "Creating the partitions on $DISK."
sudo parted -s "$DISK" mklabel gpt
sudo parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
sudo parted -s "$DISK" set 1 esp on
sudo parted -s "$DISK" mkpart ROOT 513MiB 100%

ESP="/dev/disk/by-partlabel/ESP"
ROOT="/dev/disk/by-partlabel/ROOT"

# Formatting the ESP as FAT32.
echo
info_print "Formatting the EFI Partition as FAT32."
sudo mkfs.fat -F 32 "$ESP"

# Mounting the root partition.
echo
info_print "Mounting the root partititon"
sudo mkfs.btrfs -f "$ROOT"
sudo mkdir -p /mnt
sudo mount "$ROOT" /mnt

# Creating BTRFS subvolumes.
echo
info_print "Creating BTRFS subvolumes."
subvols=(root home nix log)
for subvol in '' "${subvols[@]}"; do
    sudo btrfs su cr /mnt/@"$subvol"
done

mount_subvolumes () {
echo
info_print "Creating mountpoints and mounting the newly created subvolumes."
  sudo umount -l /mnt
  sudo mount -t btrfs -o subvol=@root,defaults,noatime,compress=zstd,discard=async,ssd "$ROOT" /mnt 
  sudo mkdir -p /mnt/{home,nix,var/log,boot} &>/dev/null
  sudo mount -t btrfs -o subvol=@home,defaults,noatime,compress=zstd,discard=async,ssd "$ROOT" /mnt/home
  sudo mount -t btrfs -o subvol=@nix,defaults,noatime,compress=zstd,discard=async,ssd "$ROOT" /mnt/nix
  sudo mount -t btrfs -o subvol=@log,defaults,noatime,compress=zstd,discard=async,ssd "$ROOT" /mnt/var/log
  sudo mount "$ESP" /mnt/boot/

  info_print "Generating the hardware-config / hardware-configuration.nix"
  sudo nixos-generate-config --root /mnt

  return 0
}


generate_systemconf () {
# Generates system config | Configuration.nix.
echo
info_print "Generating the system config / configuration.nix"
sudo rm /mnt/etc/nixos/configuration.nix &>/dev/null

timezone=$(curl -s http://ip-api.com/line?fields=timezone)

cat << EOF | sudo tee -a "/mnt/etc/nixos/configuration.nix" &>/dev/null

{ pkgs, lib, inputs, ... }:

{
  imports =
    [   # Include the results of the hardware scan.
        ./hardware-configuration.nix
    ];

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";

  # Installs Intel/AMD Microcode
  $microcode

  # Networking
  networking.networkmanager.enable = true;
  networking.hostName = "$hostname"; # Define your hostname.

  # Set your time zone.
  time.timeZone = "$timezone";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "$xtra_locale";
    LC_IDENTIFICATION = "$xtra_locale";
    LC_MEASUREMENT = "$xtra_locale";
    LC_MONETARY = "$xtra_locale";
    LC_NAME = "$xtra_locale";
    LC_NUMERIC = "$xtra_locale";
    LC_PAPER = "$xtra_locale";
    LC_TELEPHONE = "$xtra_locale";
    LC_TIME = "$xtra_locale";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.$username = {
    isNormalUser = true;
    initialPassword = "nixos";
    description = "";
    extraGroups = [ "networkmanager" "wheel" "disk" "power" "video" ];
    packages = with pkgs; [];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    wget
    btop
    git
    libvirt
    swww
    polkit_gnome
    grim
    slurp
  ];

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "JetBrainsMono" ]; })
  ];

  # Steam Configuration
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
  };

  # OpenGL
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  # Nix Package Management
  nix = {
    settings.auto-optimise-store = true;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # List services that you want to enable:
  services.openssh.enable = true;
  services.fstrim.enable = true;
  services.xserver = {
    layout = "$keyboard_layout";
    xkbVariant = "";
    libinput.enable = true;
  };

  console.keyMap = "$keyboard_layout";

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  hardware.pulseaudio.enable = false;
  sound.enable = true;
  security.rtkit.enable = true;

  # Automatic Updates
  system.autoUpgrade = {
    enable = true;
    channel = "https://nixos.org/channels/nixos-23.11";
  };
  
  nixpkgs.config.allowUnfree = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

  # Enables the use of flakes and some other nice features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

}

EOF
return 0
}

generate_userconf () {
# Generates Home-Manager - user config | Home.nix.
echo
info_print "Generating the user config (Home-Manager) / home.nix"
sudo rm /mnt/etc/nixos/home.nix &>/dev/null
cat << EOF | sudo tee -a "/mnt/etc/nixos/home.nix" &>/dev/null

{ config, pkgs, ... }:

{

      home.username = "$username";
      home.homeDirectory = "/home/$username";
      home.stateVersion = "23.11";

    # Hyprland - Tiling Window Manager Installation
    wayland.windowManager.hyprland = {
      # Whether to enable Hyprland wayland compositor
      enable = true;
  
      # The hyprland package to use
      package = pkgs.hyprland;

      # Whether to enable XWayland
      xwayland.enable = true;

      # Whether to enable hyprland-session.target on hyprland startup
      systemd.enable = true;

      # Whether to enable patching wlroots for better Nvidia support
      enableNvidiaPatches = true;
    };




  # Desktop Theming Configuration
    home.pointerCursor = {
      gtk.enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    gtk = {
      enable = true;
      theme = {
      package = pkgs.flat-remix-gtk;
      name = "Flat-Remix-GTK-Grey-Darkest";
    };

    iconTheme = {
      package = pkgs.gnome.adwaita-icon-theme;
      name = "Adwaita";
    };

    font = {
      name = "Sans";
      size = 11;
    };



};

EOF
echo
return 0
}

generate_flake () {
# Generates a flake | flake.nix.
echo
info_print "Generating a simple flake to track updates / flake.nix"
cat << EOF | sudo tee -a "/mnt/etc/nixos/flake.nix" &>/dev/null

{

  description = "HyprNix Simple Flake";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
    in {
    nixosConfigurations = {
        $hostname = lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./configuration.nix ];
        };
    };
  };

}


EOF
return 0
}

# Mount the BTRFS subvolumes
mount_subvolumes

#generate_preconf

generate_systemconf

#generate_userconf

generate_flake

sudo mkdir -p /mnt/home/$username/.dotfiles &>/dev/null
sudo cp /mnt/etc/nixos/* /mnt/home/$username/.dotfiles &>/dev/null
sudo nixos-install --no-root-passwd --flake /mnt/etc/nixos#$hostname &>/dev/null
sudo chown -R $username: /mnt/home/$username/.dotfiles &>/dev/null
echo
info_print "Rebooting!"
sleep 3
info_print "3..."
sleep 3
info_print "2..."
sleep 3
info_print "1..."
sleep 2
clear

# GoodBye screen.
echo -ne "${BOLD}${BRED}


    ▄▄▄▄·  ▄▄▄·  ▐ ▄  ▄▄ • ▄▄     
    ▐█ ▀█▪▐█ ▀█ •█▌▐█▐█ ▀ ▪██▌    
    ▐█▀▀█▄▄█▀▀█ ▐█▐▐▌▄█ ▀█▄▐█·    
    ██▄▪▐█▐█ ▪▐▌██▐█▌▐█▄▪▐█.▀     
    ·▀▀▀▀  ▀  ▀ ▀▀ █▪·▀▀▀▀  ▀     

                                                      
${RESET}"

sleep 2
sudo reboot

