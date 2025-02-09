```bash
apk add ip6tables iptables ufw 
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 8080/tcp
ufw allow 50000/tcp
ufw allow from 192.168.1.0/24
ufw allow in on cni-podman0
ufw enable
ufw reload
```

