variable "proxmox_url" {
  type    = string
  default = "https://proxmox.example:8006/api2/json"
}

variable "proxmox_username" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = "ubuntu"
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}

source "proxmox" "ubuntu" {
  pm_api_url      = var.proxmox_url
  username        = var.proxmox_username
  password        = var.proxmox_password
  node            = "proxmox-node"
  template        = false
  vm_name         = "jenkins-agent"
  cores           = 2
  memory          = 4096
  disk_size       = "20G"
  iso_file        = "local:iso/ubuntu-22.04.iso"
  ssh_username    = "ubuntu"
  ssh_password    = var.ssh_password
  ssh_timeout     = "20m"
}

build {
  sources = ["source.proxmox.ubuntu"]

  provisioner "shell" {
    inline = [
      "echo '${var.ssh_public_key}' >> /home/ubuntu/.ssh/authorized_keys",
      "sudo apt-get update",
      "sudo apt-get install -y curl",
      "curl -fsSL https://get.docker.com | sh"
    ]
  }
}
