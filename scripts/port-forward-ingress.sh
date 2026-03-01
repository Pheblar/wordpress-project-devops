#!/bin/bash
# Проброс портов Ingress на VM (0.0.0.0), чтобы с ПК по 192.168.1.31 открывался blog.corp.local
# Используются порты 8443 и 8080 (без root). Запускать на VM. Оставить в работе (Ctrl+C — остановить).
# На ПК в hosts: 192.168.1.31 blog.corp.local
# В браузере: https://blog.corp.local:8443

set -e
NS="${1:-ingress-nginx}"
SVC="ingress-nginx-controller"

if ! kubectl get svc -n "$NS" "$SVC" &>/dev/null; then
  echo "Сервис $SVC в namespace $NS не найден. Проверьте: kubectl get svc -n $NS"
  exit 1
fi

echo "Проброс на 0.0.0.0:8443 (HTTPS) и 0.0.0.0:8080 (HTTP). С ПК откройте: https://blog.corp.local:8443"
echo "Остановка: Ctrl+C"
exec kubectl port-forward --address 0.0.0.0 -n "$NS" "svc/$SVC" 8443:443 8080:80
