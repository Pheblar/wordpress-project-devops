#!/bin/bash
# Сценарий Б: "Обслуживание сервера" (Drain)
# 1. Найти ноду, где работает под MySQL
# 2. Выполнить drain
# 3. Убедиться, что под переехал и сайт работает

set -e
NAMESPACE="${1:-default}"
RELEASE="${RELEASE_NAME:-corp-blog}"

echo "Поды MySQL и их ноды:"
kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/component=mysql -o wide

NODE=$(kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/component=mysql -o jsonpath='{.items[0].spec.nodeName}')
if [ -z "$NODE" ]; then
  echo "Под MySQL не найден."
  exit 1
fi

echo ""
echo "Нода с MySQL: $NODE"
echo "Выполняю drain (игнорирую DaemonSets)..."
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --force --grace-period=60 2>/dev/null || true

echo "Ожидание переезда пода MySQL..."
sleep 15
kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/component=mysql -o wide

echo "Проверьте сайт в браузере (https://blog.corp.local). Данные не должны пропасть."
echo "Вернуть ноду: kubectl uncordon $NODE"
