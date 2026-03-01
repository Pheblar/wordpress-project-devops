#!/bin/bash
# Одна команда: развернуть весь стек блога (после setup-vm.sh и создания TLS secret)
# Использование:
#   export MYSQL_ROOT_PASSWORD='...' MYSQL_PASSWORD='...'
#   ./install-blog.sh [namespace]

set -e
NAMESPACE="${1:-default}"
RELEASE="corp-blog"
CHART_PATH="$(dirname "$0")/../helm/corp-blog"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Создать TLS secret, если есть файлы в корне проекта
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT/tls.crt" ] && [ -f "$ROOT/tls.key" ]; then
  kubectl create secret tls blog-corp-tls --cert="$ROOT/tls.crt" --key="$ROOT/tls.key" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
fi

helm upgrade --install "$RELEASE" "$CHART_PATH" \
  --namespace "$NAMESPACE" \
  -f "$CHART_PATH/values.yaml" \
  -f "$CHART_PATH/values-dev.yaml" \
  --set mysqlRootPassword="${MYSQL_ROOT_PASSWORD:?Set MYSQL_ROOT_PASSWORD}" \
  --set mysqlPassword="${MYSQL_PASSWORD:?Set MYSQL_PASSWORD}" \
  --wait --timeout 10m

echo "Установка завершена. Добавьте в hosts: $(minikube ip 2>/dev/null || echo '<INGRESS_IP>') blog.corp.local"
echo "Откройте https://blog.corp.local"
