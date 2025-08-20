source "proxmox" "ubuntu" {
  pm_api_url      = "https://192.168.1.11:8006/api2/json"
  username        = "root@pam"
  password        = "yourpassword"
  node            = "proxmox-node"
  template        = false
  vm_name         = "jenkins-agent"
  cores           = 2
  memory          = 4096
  disk_size       = "20G"
  iso_file        = "local:iso/ubuntu-22.04.iso"
  ssh_username    = "ubuntu"
  ssh_password    = "ubuntu"
  ssh_timeout     = "20m"
}

build {
  sources = ["source.proxmox.ubuntu"]

  provisioner "shell" {
    inline = [
      "echo 'your-ssh-public-key' >> /home/ubuntu/.ssh/authorized_keys",
      "sudo apt-get update",
      "sudo apt-get install -y curl",
      "curl -fsSL https://get.docker.com | sh"
    ]
  }
}
