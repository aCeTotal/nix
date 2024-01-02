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

# Formatting the LUKS Container as BTRFS.
info_print "Formatting the LUKS container as BTRFS."
sudo mkfs.btrfs "$ROOT"
sudo mkdir -p /mnt
sudo mount "$ROOT" /mnt

# Creating BTRFS subvolumes.
info_print "Creating BTRFS subvolumes."
subvols=(root home nix log)
for subvol in '' "${subvols[@]}"; do
    sudo btrfs su cr /mnt/@"$subvol"
done

# Mounting the newly created subvolumes.
umount /mnt
info_print "Mounting the newly created subvolumes."
mountopts="ssd,noatime,compress-force=zstd:3,discard=async"
sudo mkdir -p /mnt/{home,nix,/var/log,boot}
sudo mount -o "$mountopts",subvol=@root "$ROOT" /mnt
sudo mount -o "$mountopts",subvol=@home "$ROOT" /mnt/home
sudo mount -o "$mountopts",subvol=@nix "$ROOT" /mnt/nix
sudo mount -o "$mountopts",subvol=@log "$ROOT" /mnt/var/log
sudo mount "$ESP" /mnt/boot/

sudo nixos-generate-config --root /mnt



# Storing the timezone
timezone=curl http://ip-api.com/line?fields=timezone

# Checking the microcode to install.
microcode_detector

# Check if NVIDIA GPU is found
if lspci -k | grep -A 2 -E "(VGA|3D)" | grep -iq nvidia; then
info_print "NVIDIA GPU FOUND! Installing nvidia-related packages!"  
nvidia1=services.xserver.videoDrivers = ["nvidia"];

# Installing HyprNix.
info_print "Installing HyprNix!"
sudo rm /mnt/etc/nixos/configuration.nix && cat /mnt/etc/nixos/configuration.nix
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

  # Networking
  networking.networkmanager.enable = true;
  networking.hostName = "$hostname"; # Define your hostname.

  # Set your time zone.
  time.timeZone = "$timezone";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  #Remove this if you only need US Locale.
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "nb_NO.UTF-8";
    LC_IDENTIFICATION = "nb_NO.UTF-8";
    LC_MEASUREMENT = "nb_NO.UTF-8";
    LC_MONETARY = "nb_NO.UTF-8";
    LC_NAME = "nb_NO.UTF-8";
    LC_NUMERIC = "nb_NO.UTF-8";
    LC_PAPER = "nb_NO.UTF-8";
    LC_TELEPHONE = "nb_NO.UTF-8";
    LC_TIME = "nb_NO.UTF-8";
  };

  # CPU Microcode
  $microcode

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.$username = {
    isNormalUser = true;
    initialPassword = "pw123";
    description = "";
    extraGroups = [ "networkmanager" "wheel" "disk" "power" "video" ];
    packages = with pkgs; [];
  };

  fileSystems = {
  "/".options = [ "compress=zstd" ];
  "/home".options = [ "compress=zstd" ];
  "/nix".options = [ "compress=zstd" "noatime" ];
  "/swap".options = [ "noatime" ];
  };

  programs.hyprland.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # Import Scripts
    (import ../scripts/emopicker9000.nix { inherit pkgs; })
    (import ../scripts/task-waybar.nix { inherit pkgs; })
    (import ../scripts/squirtle.nix { inherit pkgs; })
    (import ../scripts/autohypr.nix { inherit pkgs; })
    # Utils
    vim
    wget
    btop
    git
    libvirt
    swww
    polkit_gnome
    grim
    slurp
    lm_sensors
    unzip
    unrar
    gnome.file-roller
    libnotify
    swaynotificationcenter
    tofi
    xfce.thunar
    imv
    killall
    v4l-utils
    # Misc
    ydotool
    wl-clipboard
    socat
    cowsay
    lsd
    neofetch
    pkg-config
    cmatrix
    lolcat
    transmission-gtk
    # Photo & Video
    mpv
    gimp
    obs-studio
    blender
    kdenlive
    # Online
    firefox
    discord
    # Dev
    meson
    glibc
    hugo
    gnumake
    ninja
    go
    nodejs_21
    godot_4
    rustup
    rust-analyzer
    # Audio
    pavucontrol
    audacity
    # Gaming
    zeroad
    xonotic
    openra
    # Fonts
    font-awesome
    symbola
    noto-fonts-color-emoji
    material-icons
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

  #Nvidia stuff if found
  $nvidia1

  # Nix Package Management
  nix = {
    settings.auto-optimise-store = true;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Set Environment Variables
  environment.variables={
   NIXOS_OZONE_WL = "1";
   PATH = [
     "\${HOME}/.local/bin"
     "\${HOME}/.cargo/bin"
     "\$/usr/local/bin"
   ];
   NIXPKGS_ALLOW_UNFREE = "1";
   SCRIPTDIR = "\${HOME}/.local/share/scriptdeps";
   STARSHIP_CONFIG = "\${HOME}/.config/starship/starship.toml";
   XDG_CURRENT_DESKTOP = "Hyprland";
   XDG_SESSION_TYPE = "wayland";
   XDG_SESSION_DESKTOP = "Hyprland";
   GDK_BACKEND = "wayland";
   CLUTTER_BACKEND = "wayland";
   SDL_VIDEODRIVER = "x11";
   XCURSOR_SIZE = "24";
   XCURSOR_THEME = "Bibata-Modern-Ice";
   QT_QPA_PLATFORM = "wayland";
   QT_QPA_PLATFORMTHEME = "qt5ct";
   QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
   QT_AUTO_SCREEN_SCALE_FACTOR = "1";
   MOZ_ENABLE_WAYLAND = "1";
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
    layout = "us";
    xkbVariant = "";
    libinput.enable = true;
  };
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

}

EOF

# Creating Home.nix for Home-Manager.
sudo rm /mnt/etc/nixos/home.nix && cat /mnt/etc/nixos/home.nix
cat << EOF | sudo tee -a /mnt/etc/nixos/home.nix

{ config, pkgs, ... }:

let
  home-manager = builtins.fetchTarball "https://github.com/nix-community/home-manager/archive/release-23.11.tar.gz";
in
{
  imports = [
    (import "${home-manager}/nixos")
  ];

  home-manager.users.$username = {

  home.username = "$username";
  home.homeDirectory = "/home/$username";
  home.stateVersion = "23.11";

  home.file.".config/swaync/config.json" = {
    source = ../configfiles/swaync/config.json;
    recursive = true;
  };
  home.file.".Xresources" = {
    source = ../configfiles/.Xresources;
    recursive = true;
  };
  home.file.".vimrc" = {
    source = ../configfiles/.vimrc;
    recursive = true;
  };
  home.file.".config/tofi/config" = {
    source = ../configfiles/tofi/config;
    recursive = true;
  };
  home.file.".config/wallpaper.png" = {
    source = ../configfiles/wallpaper.png;
    recursive = true;
  };
  home.file.".config/swaync/style.css" = {
    source = ../configfiles/swaync/style.css;
    recursive = true;
  };
  home.file.".config/pipewire/pipewire.conf" = {
    source = ../configfiles/pipewire/pipewire.conf;
    recursive = true;
  };
  home.file.".config/neofetch/config.conf" = {
    source = ../configfiles/neofetch/config.conf;
    recursive = true;
  };
  home.file.".local/share/scriptdeps/emoji" = {
    source = ../configfiles/emoji;
    recursive = true;
  };
  home.file.".config/hypr/hyprland.conf" = {
    source = ../configfiles/hypr/hyprland.conf;
    recursive = true;
  };
  home.file.".config/hypr/keybindings.conf" = {
    source = ../configfiles/hypr/keybindings.conf;
    recursive = true;
  };
  home.file.".config/hypr/theme.conf" = {
    source = ../configfiles/hypr/theme.conf;
    recursive = true;
  };
  home.file.".config/hypr/animations.conf" = {
    source = ../configfiles/hypr/animations.conf;
    recursive = true;
  };
  home.file.".config/hypr/autostart.conf" = {
    source = ../configfiles/hypr/autostart.conf;
    recursive = true;
  };
  home.file.".config/zaney-stinger.mov" = {
    source = ../configfiles/zaney-stinger.mov;
    recursive = true;
  };
  home.file.".local/share/fonts/UniSans-Heavy.otf" = {
    source = ../configfiles/UniSans-Heavy.otf;
    recursive = true;
  };
  home.pointerCursor = {
      gtk.enable = true;
      # x11.enable = true;
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 24;
  };
  qt.enable = true;
  qt.platformTheme = "gtk";
  qt.style.name = "adwaita-dark";
  qt.style.package = pkgs.adwaita-qt;
  gtk = {
      enable = true;
      font = {
	name = "Ubuntu";
	size = 12;
	package = pkgs.ubuntu_font_family;
    };
    theme = {
        name = "Tokyonight-Storm-BL";
        package = pkgs.tokyo-night-gtk;
    };
    iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
        name = "Bibata-Modern-Ice";
        package = pkgs.bibata-cursors;
    };
    gtk3.extraConfig = {
        Settings = ''
        gtk-application-prefer-dark-theme=1
        '';
    };
    gtk4.extraConfig = {
        Settings = ''
        gtk-application-prefer-dark-theme=1
        '';
    };
  };
  xdg = {
    userDirs = {
        enable = true;
        createDirectories = true;
    };
  };
  programs = {
    kitty = {
      enable = true;
      package = pkgs.kitty;
      font.name = "JetBrainsMono Nerd Font";
      font.size = 16;
      settings = {
        scrollback_lines = 2000;
        wheel_scroll_min_lines = 1;
        window_padding_width = 6;
        confirm_os_window_close = 0;
        background_opacity = "0.85";
      };
      extraConfig = ''
          foreground #a9b1d6
          background #1a1b26
          color0 #414868
          color8 #414868
          color1 #f7768e
          color9 #f7768e
          color2  #73daca
          color10 #73daca
          color3  #e0af68
          color11 #e0af68
          color4  #7aa2f7
          color12 #7aa2f7
          color5  #bb9af7
          color13 #bb9af7
          color6  #7dcfff
          color14 #7dcfff
          color7  #c0caf5
          color15 #c0caf5
          cursor #c0caf5
          cursor_text_color #1a1b26
          selection_foreground none
          selection_background #28344a
          url_color #9ece6a
          active_border_color #3d59a1
          inactive_border_color #101014
          bell_border_color #e0af68
          tab_bar_style fade
          tab_fade 1
          active_tab_foreground   #3d59a1
          active_tab_background   #16161e
          active_tab_font_style   bold
          inactive_tab_foreground #787c99
          inactive_tab_background #16161e
          inactive_tab_font_style bold
          tab_bar_background #101014
      '';
    };
    bash = {
      enable = true;
      enableCompletion = true;
      sessionVariables = {
      
      };
      shellAliases = {
        sv="sudo vim";
	v="vim";
        ls="lsd";
        ll="lsd -l";
        la="lsd -a";
        lal="lsd -al";
        ".."="cd ..";
      };
    };
    waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = [{
	layer = "top";
	position = "top";

	modules-left = [ "hyprland/window" ];
	modules-center = [ "network" "pulseaudio" "cpu" "hyprland/workspaces" "memory" "disk" "clock" ];
	modules-right = [ "custom/notification" "tray" ];
	"hyprland/workspaces" = {
        	format = "{icon}";
        	format-icons = {
            		default = " ";
            		active = " ";
            		urgent = " ";
	};
        on-scroll-up = "hyprctl dispatch workspace e+1";
        on-scroll-down = "hyprctl dispatch workspace e-1";
    	};
	"clock" = {
        format = "{: %I:%M %p}";
		tooltip = false;
	};
	"hyprland/window" = {
		max-length = 60;
		separate-outputs = false;
	};
	"memory" = {
		interval = 5;
		format = " {}%";
	};
	"cpu" = {
		interval = 5;
		format = " {usage:2}%";
        tooltip = false;
	};
    "disk" = {
        format = "  {free}/{total}";
        tooltip = true;
    };
    "network" = {
        format-icons = ["󰤯" "󰤟" "󰤢" "󰤥" "󰤨"];
        format-ethernet = ": {bandwidthDownOctets} : {bandwidthUpOctets}";
        format-wifi = "{icon} {signalStrength}%";
        format-disconnected = "󰤮";
    };
	"tray" = {
		spacing = 12;
	};
    "pulseaudio" = {
        format = "{icon} {volume}% {format_source}";
        format-bluetooth = "{volume}% {icon} {format_source}";
        format-bluetooth-muted = " {icon} {format_source}";
        format-muted = " {format_source}";
        format-source = " {volume}%";
        format-source-muted = "";
        format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = ["" "" ""];
        };
        	on-click = "pavucontrol";
    };
    "custom/notification" = {
        tooltip = false;
        format = "{icon} {}";
        format-icons = {
            notification = "<span foreground='red'><sup></sup></span>";
            none = "";
            dnd-notification = "<span foreground='red'><sup></sup></span>";
            dnd-none = "";
            inhibited-notification = "<span foreground='red'><sup></sup></span>";
            inhibited-none = "";
            dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
            dnd-inhibited-none = "";
       	};
        	return-type = "json";
        	exec-if = "which swaync-client";
        	exec = "swaync-client -swb";
       		on-click = "task-waybar";
        	escape = true;
    };
    "battery" = {
        states = {
            warning = 30;
            critical = 15;
        };
        format = "{icon} {capacity}%";
        format-charging = "󰂄 {capacity}%";
        format-plugged = "󱘖 {capacity}%";
        format-icons = ["󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
        on-click = "";
        tooltip = false;
    };
    }];
      style = ''
	* {
		font-size: 16px;
		font-family: Ubuntu Nerd Font, Font Awesome, sans-serif;
    		font-weight: bold;
	}
	window#waybar {
		    background-color: rgba(26,27,38,0);
    		border-bottom: 1px solid rgba(26,27,38,0);
    		border-radius: 0px;
		    color: #f8f8f2;
	}
	#workspaces {
		    background: linear-gradient(180deg, #414868, #24283b);
    		margin: 5px;
    		padding: 0px 1px;
    		border-radius: 15px;
    		border: 0px;
    		font-style: normal;
    		color: #15161e;
	}
	#workspaces button {
    		padding: 0px 5px;
    		margin: 4px 3px;
    		border-radius: 15px;
    		border: 0px;
    		color: #15161e;
    		background-color: #1a1b26;
    		opacity: 1.0;
    		transition: all 0.3s ease-in-out;
	}
	#workspaces button.active {
    		color: #15161e;
    		background: #7aa2f7;
    		border-radius: 15px;
    		min-width: 40px;
    		transition: all 0.3s ease-in-out;
    		opacity: 1.0;
	}
	#workspaces button:hover {
    		color: #15161e;
    		background: #7aa2f7;
    		border-radius: 15px;
    		opacity: 1.0;
	}
	tooltip {
  		background: #1a1b26;
  		border: 1px solid #7aa2f7;
  		border-radius: 10px;
	}
	tooltip label {
  		color: #c0caf5;
	}
	#window {
    		color: #565f89;
    		background: #1a1b26;
    		border-radius: 0px 15px 50px 0px;
    		margin: 5px 5px 5px 0px;
    		padding: 2px 20px;
	}
	#memory {
    		color: #2ac3de;
    		background: #1a1b26;
    		border-radius: 15px 50px 15px 50px;
    		margin: 5px;
    		padding: 2px 20px;
	}
	#clock {
    		color: #c0caf5;
    		background: #1a1b26;
    		border-radius: 15px 50px 15px 50px;
    		margin: 5px;
    		padding: 2px 20px;
	}
	#cpu {
    		color: #b4f9f8;
    		background: #1a1b26;
    		border-radius: 50px 15px 50px 15px;
    		margin: 5px;
    		padding: 2px 20px;
	}
	#disk {
    		color: #9ece6a;
    		background: #1a1b26;
    		border-radius: 15px 50px 15px 50px;
    		margin: 5px;
    		padding: 2px 20px;
	}
	#battery {
    		color: #f7768e;
    		background: #1a1b26;
    		border-radius: 15px;
    		margin: 5px;
    		padding: 2px 20px;
	}
	#network {
    		color: #ff9e64;
    		background: #1a1b26;
    		border-radius: 50px 15px 50px 15px;
    		margin: 5px;
    		padding: 2px 20px;
	}
	#tray {
    		color: #bb9af7;
    		background: #1a1b26;
    		border-radius: 15px 0px 0px 50px;
    		margin: 5px 0px 5px 5px;
    		padding: 2px 20px;
	}
	#pulseaudio {
    		color: #bb9af7;
    		background: #1a1b26;
    		border-radius: 50px 15px 50px 15px;
    		margin: 5px;
    		padding: 2px 20px;
	}
	#custom-notification {
    		color: #7dcfff;
    		background: #1a1b26;
    		border-radius: 15px 50px 15px 50px;
    		margin: 5px;
    		padding: 2px 20px;
	}
      '';
    };
  };
  };
}

EOF


cd /mnt
sudo nixos-install
cd && cd nix
sudo cp -r configfiles/ /etc/
sudo cp -r scripts/ /etc/


# Finishing up.
info_print "Almost done!"
info_print "1. Type reboot and hit enter to reboot the system."
info_print "2. Log in with your user and password."
info_print "3. bash <(curl -sL bit.ly/install_hyprarch)"
info_print "4. Reboot."
info_print "GOOD LUCK! :)"
exit
