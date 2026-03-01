#!/bin/bash
# Полный сброс MySQL: удалить под и PVC, чтобы получить чистый диск.
# Использовать при ошибке "data files are corrupt or the database was not shut down cleanly".
# Данные БД будут потеряны. После скрипта нужно: helm upgrade --install ...
set -e
NAMESPACE="${1:-default}"

echo "1. Масштабируем StatefulSet MySQL до 0 реплик..."
kubectl scale statefulset corp-blog-mysql -n "$NAMESPACE" --replicas=0

echo "2. Ждём удаления пода (до 60 сек)..."
for i in $(seq 1 30); do
  if ! kubectl get pod corp-blog-mysql-0 -n "$NAMESPACE" 2>/dev/null | grep -q .; then
    echo "   Под удалён."
    break
  fi
  sleep 2
done

echo "3. Удаляем PVC data-corp-blog-mysql-0..."
kubectl delete pvc data-corp-blog-mysql-0 -n "$NAMESPACE" --ignore-not-found=true --wait=false
sleep 3
# Дождаться реального удаления (PVC может висеть в Terminating, пока под держит том — под уже нет)
for i in $(seq 1 30); do
  if ! kubectl get pvc data-corp-blog-mysql-0 -n "$NAMESPACE" 2>/dev/null | grep -q .; then
    echo "   PVC удалён."
    break
  fi
  echo "   Ожидание удаления PVC... ($i)"
  sleep 2
done

echo "4. Готово. Запустите установку/обновление блога."
echo "   В Minikube после удаления PVC том может всё равно содержать старые данные — лучше использовать wipeDataOnStart:"
echo "   helm upgrade --install corp-blog ./helm/corp-blog -n $NAMESPACE \\"
echo "     -f helm/corp-blog/values.yaml -f helm/corp-blog/values-dev.yaml \\"
echo "     --set mysqlRootPassword=\"\$MYSQL_ROOT_PASSWORD\" --set mysqlPassword=\"\$MYSQL_PASSWORD\" \\"
echo "     --set mysql.wipeDataOnStart=true --wait --timeout 10m"
