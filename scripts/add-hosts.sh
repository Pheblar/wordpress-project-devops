#!/bin/bash
# Добавить blog.corp.local в /etc/hosts (на машине, с которой заходите в браузер)
# На Windows: отредактируйте C:\Windows\System32\drivers\etc\hosts от имени администратора
# На Linux/Mac: sudo ./add-hosts.sh

INGRESS_IP="${1:-192.168.1.31}"
# Если Minikube на той же VM, получить IP: minikube ip
# Если заходите с другой машины — укажите IP вашей VM: 192.168.1.31

LINE="${INGRESS_IP} blog.corp.local"
if grep -q "blog.corp.local" /etc/hosts 2>/dev/null; then
    echo "blog.corp.local уже есть в /etc/hosts"
else
    echo "$LINE" | sudo tee -a /etc/hosts
    echo "Добавлено: $LINE"
fi
