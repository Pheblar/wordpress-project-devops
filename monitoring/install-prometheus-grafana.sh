#!/bin/bash
# Установка Prometheus + Grafana в кластер (Helm)
# Дашборд для CPU/RAM подов: импортировать по ID 315 (Kubernetes Cluster Monitoring) или 6417 (Kubernetes / Views Pods)

set -e
NAMESPACE="${1:-monitoring}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Стек тяжёлый; на кластере из 3 нод по 2GB установка может занять 10–15 минут.
# Grafana на слабом кластере не успевает подняться до срабатывания liveness — ослабляем пробы.
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --set grafana.livenessProbe.initialDelaySeconds=120 \
  --set grafana.livenessProbe.failureThreshold=10 \
  --set grafana.readinessProbe.initialDelaySeconds=90 \
  --set grafana.readinessProbe.failureThreshold=10 \
  --wait --timeout 15m

echo "Доступ к Grafana: kubectl port-forward -n $NAMESPACE svc/kube-prometheus-grafana 3000:80"
echo "  С ПК по сети: kubectl port-forward --address 0.0.0.0 -n $NAMESPACE svc/kube-prometheus-grafana 3000:80  →  http://<IP_VM>:3000"
echo "Логин: admin, пароль: admin"
echo "Дашборд для подов: в Grafana Import -> ID 6417 (Kubernetes / Views Pods) или 315"
