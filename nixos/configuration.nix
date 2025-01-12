{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];
    
  nix.nixPath = [
      "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
      "nixos-config=/home/mateuszg/IdeaProjects/mati-lab/nixos/configuration.nix"
      "/nix/var/nix/profiles/per-user/root/channels"
    ];


  # Bootloader settings
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking = {
    hostName = "mati-lab"; # System hostname
    domain = "local";
    extraHosts = ''
		127.0.0.1 mati-lab.local
		192.168.1.148 jenkins.local prometheus.local
    '';
    wireless = {
    	enable = true;
    	networks = {
    		"konewka" = {
    			psk = "2Long2Remember";	
    		};
    	};
    };
    interfaces.wlan0.useDHCP = true;
  };

  # Time and locale settings
  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pl_PL.UTF-8";
    LC_IDENTIFICATION = "pl_PL.UTF-8";
    LC_MEASUREMENT = "pl_PL.UTF-8";
    LC_MONETARY = "pl_PL.UTF-8";
    LC_NAME = "pl_PL.UTF-8";
    LC_NUMERIC = "pl_PL.UTF-8";
    LC_PAPER = "pl_PL.UTF-8";
    LC_TELEPHONE = "pl_PL.UTF-8";
    LC_TIME = "pl_PL.UTF-8";
  };

  # User configuration
  users.users.mateuszg = {
    isNormalUser = true;
    description = "Mateusz Goral";
    shell = pkgs.zsh;
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    
    packages = with pkgs; [];
  };

  # Services
  services.getty.autologinUser = "mateuszg"; # Auto-login for the user
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
    settings.PasswordAuthentication = false;
    settings.AllowUsers = [
    	"mateuszg"
    ];
  };
  virtualisation.docker.enable = true;

  services.avahi = {
  	enable = true;
  	nssmdns4 = true;
  	publish = {
  		enable = true;
  		addresses = true;
  	};
  };

  # Programs
  programs.zsh.enable = true;

  # System-wide packages
  environment.systemPackages = with pkgs; [
	avahi
    micro
    wget
    git
    zsh
    vim
    openssh
    docker
    docker-compose
  ];

  networking.firewall = {
 	enable = true;
  	allowedUDPPorts = [ 5353 22 ];	
  	allowedTCPPorts = [ 5353 22 80 443 ];	
  };

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "24.11";
}
