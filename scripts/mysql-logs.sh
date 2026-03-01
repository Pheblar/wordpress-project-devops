#!/bin/bash
# Собрать логи MySQL-пода (текущий и предыдущий контейнер) — чтобы понять причину CrashLoopBackOff
NAMESPACE="${1:-default}"
POD="corp-blog-mysql-0"

echo "=== Pod status ==="
kubectl get pod "$POD" -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "=== Logs (current container) ==="
kubectl logs "$POD" -n "$NAMESPACE" -c mysql --tail=200 2>/dev/null || echo "(no current logs)"

echo ""
echo "=== Logs (previous container, after last crash) ==="
kubectl logs "$POD" -n "$NAMESPACE" -c mysql --previous --tail=200 2>/dev/null || echo "(no previous logs)"

echo ""
echo "=== Describe pod (events) ==="
kubectl describe pod "$POD" -n "$NAMESPACE" | tail -30
