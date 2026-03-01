#!/bin/bash
# Установка Prometheus + Grafana в кластер (Helm)
# Дашборд для CPU/RAM подов: импортировать по ID 315 (Kubernetes Cluster Monitoring) или 6417 (Kubernetes / Views Pods)

set -e
NAMESPACE="${1:-monitoring}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set grafana.adminPassword=admin \
  --wait --timeout 5m

echo "Доступ к Grafana (порт-форвард): kubectl port-forward -n $NAMESPACE svc/kube-prometheus-grafana 3000:80"
echo "Логин: admin, пароль: admin"
echo "Дашборд для подов: в Grafana Import -> ID 6417 (Kubernetes / Views Pods) или 315"
