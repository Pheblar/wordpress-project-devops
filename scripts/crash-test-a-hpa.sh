#!/bin/bash
# Сценарий А: "Трафик пошёл" (HPA)
# Требуется: чарт установлен с environment=prod (или autoscaling.enabled=true) и metrics-server
# Запуск: ./crash-test-a-hpa.sh [namespace]

NAMESPACE="${1:-default}"
RELEASE="${RELEASE_NAME:-corp-blog}"
SVC="${RELEASE}-wordpress"

echo "Текущее количество подов WordPress:"
kubectl get deployment -n "$NAMESPACE" "$RELEASE-wordpress" -o jsonpath='{.spec.replicas}' 2>/dev/null && echo " replicas"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=corp-blog,app.kubernetes.io/component=wordpress

echo ""
echo "Запуск нагрузочного теста (curl в цикле). Остановить: Ctrl+C"
echo "В другом терминале смотрите: watch -n2 'kubectl get hpa,pods -n $NAMESPACE'"

# Получить URL (Minikube tunnel или port-forward или внутренний curl)
URL="http://${SVC}.${NAMESPACE}.svc.cluster.local"
if command -v hey &>/dev/null; then
  hey -z 120s -c 50 "$URL"
else
  for i in $(seq 1 300); do
    curl -s -o /dev/null "$URL" &
  done
  wait
fi

echo "После теста проверьте: kubectl get hpa -n $NAMESPACE"
