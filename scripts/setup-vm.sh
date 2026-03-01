#!/bin/bash
# Подготовка VM Ubuntu 24.04: Docker, Minikube (3 ноды), Helm, kubectl
# Запускать от root или через sudo: sudo bash setup-vm.sh

set -e

echo "==> Обновление системы и установка зависимостей..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common

echo "==> Установка Docker..."
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable docker
    systemctl start docker
else
    echo "Docker уже установлен."
fi

echo "==> Установка kubectl..."
if ! command -v kubectl &>/dev/null; then
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ stable main" | tee /etc/apt/sources.list.d/kubernetes.list
    apt-get update -y
    apt-get install -y kubectl
else
    echo "kubectl уже установлен."
fi

echo "==> Установка Minikube..."
if ! command -v minikube &>/dev/null; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    install minikube-linux-amd64 /usr/local/bin/minikube
    rm -f minikube-linux-amd64
else
    echo "Minikube уже установлен."
fi

echo "==> Установка Helm..."
if ! command -v helm &>/dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "Helm уже установлен."
fi

echo "==> Запуск Minikube с 3 нодами (1 control-plane + 2 workers)..."
# 8GB RAM, 8 CPU: 3 ноды по 2GB, по 2 CPU на ноду (можно задать MINIKUBE_MEMORY / MINIKUBE_CPUS)
MINIKUBE_MEM="${MINIKUBE_MEMORY:-2048}"
MINIKUBE_CPU="${MINIKUBE_CPUS:-2}"
minikube delete --all 2>/dev/null || true
minikube start --driver=docker --nodes=3 --cpus="${MINIKUBE_CPU}" --memory="${MINIKUBE_MEM}"

echo "==> Включение addons: ingress, metrics-server (для HPA)..."
minikube addons enable ingress
minikube addons enable metrics-server

echo "==> Установка default StorageClass (standard в Minikube уже есть)..."
kubectl get storageclass
echo "Готово. Проверка нод:"
kubectl get nodes -o wide
