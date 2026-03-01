#!/bin/bash
# Сценарий В: "Защита от дурака" (PDB)
# PDB minAvailable: 1 не даст выключить ноду с последним подом WordPress,
# пока не будет достаточно реплик на других нодах.

NAMESPACE="${1:-default}"
RELEASE="${RELEASE_NAME:-corp-blog}"

echo "Текущий PDB:"
kubectl get pdb -n "$NAMESPACE"

echo ""
echo "Поды WordPress по нодам:"
kubectl get pod -n "$NAMESPACE" -l app.kubernetes.io/component=wordpress -o wide

echo ""
echo "Попробуйте drain ноды, где живут реплики WordPress."
echo "Если реплика одна и PDB minAvailable=1, drain этой ноды будет заблокирован (или завершится только после переезда пода)."
echo "Пример: kubectl drain <node> --ignore-daemonsets"
