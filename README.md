# Корпоративный блог (On-Prem Simulation)

Отказоустойчивый внутренний блог: Kubernetes, Helm, WordPress, MySQL, Prometheus/Grafana, TLS.

**Сервер:** Ubuntu 24.04.4 LTS (рекомендуется 8GB RAM, 8 CPU). IP VM в сети, например 192.168.1.31.

---

## Быстрый старт (свежая машина)

На новой Ubuntu скопируйте проект на сервер и выполните по порядку.

**Шаг 1 — Кластер (один раз):**
```bash
cd ~/wordpress-project-devops   # или путь к проекту
sudo bash scripts/setup-vm.sh
```
Проверка: `kubectl get nodes` (должно быть 3 ноды).

**Шаг 2 — Сертификат и TLS Secret:**
```bash
bash scripts/gen-tls-cert.sh .
kubectl create secret tls blog-corp-tls --cert=tls.crt --key=tls.key -n default
```

**Шаг 3 — Установка блога (Helm):**
```bash
export MYSQL_ROOT_PASSWORD='YourRootPass' MYSQL_PASSWORD='WpUserPass'

helm install corp-blog ./helm/corp-blog -n default \
  -f helm/corp-blog/values.yaml \
  -f helm/corp-blog/values-dev.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" \
  --set mysqlPassword="$MYSQL_PASSWORD" \
  --wait --timeout 10m
```
Дождитесь окончания (до 10 мин). Альтернатива: `bash scripts/install-blog.sh default` — то же самое плюс автосоздание TLS Secret из `tls.crt`/`tls.key`, если они лежат в корне проекта.

**Шаг 4 — Доступ с браузера:**

- На VM в отдельном терминале (оставить работать):
  ```bash
  kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 8443:443 8080:80
  ```
- На ПК в `C:\Windows\System32\drivers\etc\hosts` добавить (от администратора): `192.168.1.31 blog.corp.local`
- В браузере открыть: **https://blog.corp.local:8443** (предупреждение о сертификате — принять).

**Шаг 5 — Первый заход:** в браузере пройти установку WordPress (язык, логин, пароль).

Дальше: мониторинг, RBAC, краш-тесты — в [пошаговой инструкции](#пошаговая-инструкция) ниже.

---

## Пошаговая инструкция

### 1. Подготовка VM

На Ubuntu 24.04 (192.168.1.31):

```bash
# Скопировать проект на сервер, затем:
sudo bash scripts/setup-vm.sh
```

Устанавливаются: Docker, kubectl, Minikube (3 ноды), Helm. Запускается Minikube с addons: **ingress**, **metrics-server**.

Проверка:

```bash
kubectl get nodes
kubectl get storageclass   # default StorageClass должен быть
```

**Если Minikube не стартует:** память в `--memory` задаётся **на каждую ноду**. По умолчанию 3 ноды × 2GB (под 8GB VM). На слабых машинах уменьшите: `export MINIKUBE_MEMORY=1024` перед скриптом или запуск вручную с `--memory=1024`.

### 2. TLS-сертификат для blog.corp.local

На сервере (или локально, затем скопировать файлы):

```bash
bash scripts/gen-tls-cert.sh .
# Создаст tls.crt и tls.key
```

Создать Secret в кластере (namespace должен совпадать с тем, куда ставите блог):

```bash
kubectl create namespace default --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls blog-corp-tls --cert=tls.crt --key=tls.key -n default
```

### 3. Установка блога (Helm)

**Без хардкода паролей** — передать через переменные или отдельный values:

```bash
export MYSQL_ROOT_PASSWORD='YourRootPassword'
export MYSQL_PASSWORD='WordPressDbPassword'

helm upgrade --install corp-blog ./helm/corp-blog \
  -n default \
  -f helm/corp-blog/values.yaml \
  -f helm/corp-blog/values-dev.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" \
  --set mysqlPassword="$MYSQL_PASSWORD" \
  --wait --timeout 10m
```

**Prod** (3 реплики WordPress, HPA):

```bash
helm upgrade --install corp-blog ./helm/corp-blog \
  -n default \
  -f helm/corp-blog/values.yaml \
  -f helm/corp-blog/values-prod.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" \
  --set mysqlPassword="$MYSQL_PASSWORD" \
  --wait --timeout 10m
```

Проверка: поды и сервисы в состоянии Running.

**Если ошибка «context deadline exceeded»:** релиз ставится, но поды не успевают стать Ready за таймаут. Посмотрите причину:
`kubectl get pods -n default -l app.kubernetes.io/instance=corp-blog` и `kubectl describe pod -n default -l app.kubernetes.io/component=mysql`. Часто MySQL долго инициализирует данные при первом запуске — просто повторите ту же команду `helm upgrade --install ...` (таймаут теперь 10 мин, пробы MySQL ослаблены).

**Если MySQL в CrashLoopBackOff** (много рестартов): возможны повреждённые данные на диске, OOM или ошибка конфига. Сначала посмотрите логи контейнера:

```bash
./scripts/mysql-logs.sh default
# или: kubectl logs corp-blog-mysql-0 -n default --previous
```

Чистый старт при **повреждённых данных** (в логах: «data files are corrupt or the database was not shut down cleanly»). В Minikube удаление PVC не всегда очищает hostPath — используйте **вариант 1**:

```bash
# Вариант 1 (рекомендуется): принудительная очистка тома перед стартом MySQL (без удаления PVC)
helm upgrade --install corp-blog ./helm/corp-blog -n default \
  -f helm/corp-blog/values.yaml -f helm/corp-blog/values-dev.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" --set mysqlPassword="$MYSQL_PASSWORD" \
  --set mysql.wipeDataOnStart=true

# Важно: StatefulSet не пересоздаёт под при смене только шаблона — удалите под, чтобы поднялся новый с init-контейнером (wipe).
kubectl delete pod corp-blog-mysql-0 -n default

# Дождаться Ready (можно снова helm upgrade с --wait или смотреть kubectl get pods -w)
helm upgrade corp-blog ./helm/corp-blog -n default \
  -f helm/corp-blog/values.yaml -f helm/corp-blog/values-dev.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" --set mysqlPassword="$MYSQL_PASSWORD" \
  --set mysql.wipeDataOnStart=true --wait --timeout 10m

# После успешного запуска отключите wipe, чтобы при следующих рестартах данные не стирались:
helm upgrade corp-blog ./helm/corp-blog -n default \
  -f helm/corp-blog/values.yaml -f helm/corp-blog/values-dev.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" --set mysqlPassword="$MYSQL_PASSWORD" \
  --set mysql.wipeDataOnStart=false
```

```bash
# Вариант 2: удалить PVC (скрипт или вручную), затем helm upgrade
./scripts/mysql-reset-pvc.sh default
helm upgrade --install corp-blog ./helm/corp-blog -n default \
  -f helm/corp-blog/values.yaml -f helm/corp-blog/values-dev.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" --set mysqlPassword="$MYSQL_PASSWORD" \
  --wait --timeout 10m
```

### 4. Доступ по домену и HTTPS

- **Minikube:** IP Minikube (192.168.49.2) доступен только с самой VM. Чтобы заходить **с вашего ПК** по домену blog.corp.local:

  1. **На VM** запустите проброс портов (порты 8443/8080, чтобы не требовать root):
     ```bash
     kubectl port-forward --address 0.0.0.0 -n ingress-nginx svc/ingress-nginx-controller 8443:443 8080:80
     ```
     Или: `bash scripts/port-forward-ingress.sh`. Оставьте команду в работе (Ctrl+C — остановить).

  2. **На ПК** в `C:\Windows\System32\drivers\etc\hosts` добавьте (от имени администратора):
     ```
     192.168.1.31 blog.corp.local
     ```

  3. В браузере откройте **https://blog.corp.local:8443** (предупреждение о сертификате — принять).

- Если браузер на **той же VM**: в hosts укажите `127.0.0.1 blog.corp.local`, запустите `kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8443:443 8080:80`, откройте https://blog.corp.local:8443.

Скрипт-подсказка (на машине, где правите hosts):

```bash
# Linux/Mac:
sudo bash scripts/add-hosts.sh 192.168.1.31
```

Откройте в браузере: **https://blog.corp.local:8443**. Должно открыться с предупреждением о самоподписанном сертификате — это ожидаемо.

**Если 502 Bad Gateway:** Ingress не получает ответ от WordPress. Часто WordPress поднялся до MySQL и не видит БД. Проверьте и перезапустите WordPress:

```bash
kubectl get pods -n default -l app.kubernetes.io/instance=corp-blog
kubectl logs -n default -l app.kubernetes.io/component=wordpress --tail=50
kubectl rollout restart deployment corp-blog-wordpress -n default
```

Подождите минуту, пока под перезапустится, и обновите страницу.

### 5. Мониторинг (Prometheus + Grafana)

```bash
bash monitoring/install-prometheus-grafana.sh monitoring
```

Доступ к Grafana:

- **С той же VM:** `kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80` → в браузере http://localhost:3000
- **С вашего ПК:** порт-форвард должен слушать на всех интерфейсах, иначе 192.168.1.31:3000 не ответит:
  ```bash
  kubectl port-forward --address 0.0.0.0 -n monitoring svc/kube-prometheus-grafana 3000:80
  ```
  В браузере на ПК: http://192.168.1.31:3000

Логин **admin**, пароль **admin**.

**Дашборд по CPU/RAM подов:** в Grafana: Dashboards → Import → ввести ID **6417** (Kubernetes / Views Pods) или **315** (Kubernetes Cluster Monitoring) → Load.

### 6. RBAC (junior-dev)

Права только на просмотр логов и списка подов в namespace проекта:

```bash
# Подставить нужный namespace (например default)
kubectl apply -f rbac/junior-dev.yaml -n default
```

Проверка (должно быть **no**):

```bash
kubectl auth can-i delete pod --as=system:serviceaccount:default:junior-dev
```

Просмотр логов/списка подов — **yes**:

```bash
kubectl auth can-i get pods --as=system:serviceaccount:default:junior-dev
kubectl auth can-i get pods/log --as=system:serviceaccount:default:junior-dev
```

### 7. Crash Test (проверка отказоустойчивости)

**Сценарий А — HPA ("трафик пошёл"):**

- Установить чарт в prod-режиме (HPA включён). Если до этого стоял **dev**, при переходе на prod нельзя менять размер тома MySQL (StatefulSet) — укажите текущий размер (в dev это 3Gi):

```bash
helm upgrade corp-blog ./helm/corp-blog -n default \
  -f helm/corp-blog/values.yaml -f helm/corp-blog/values-prod.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" --set mysqlPassword="$MYSQL_PASSWORD" \
  --set mysql.persistence.size=3Gi
```

Затем нагрузка и наблюдение за HPA:

```bash
# В одном терминале
watch -n2 'kubectl get hpa,pods -n default'

# В другом — нагрузка (с самой VM)
kubectl run curl --rm -it --restart=Never --image=curlimages/curl -- sh -c 'while true; do curl -s -o /dev/null http://corp-blog-wordpress.default.svc.cluster.local; done'
```

Ожидание: количество подов WordPress увеличивается при росте CPU.

**Сценарий Б — Drain ("обслуживание сервера"):**

```bash
# На какой ноде MySQL
kubectl get pod -l app.kubernetes.io/component=mysql -o wide

# Drain этой ноды (подставить NODE_NAME)
kubectl drain NODE_NAME --ignore-daemonsets --delete-emptydir-data --force --grace-period=60
```

Ожидание: под MySQL переезжает на другую ноду, данные не теряются. Проверить сайт. Вернуть ноду: `kubectl uncordon NODE_NAME`.

**Сценарий В — PDB ("защита от дурака"):**

PDB для WordPress с `minAvailable: 1` уже включён в чарт. При drain ноды, где осталась последняя реплика WordPress, Kubernetes не завершит под, пока не будет доступна другая реплика (или заблокирует eviction).

---

## Структура проекта

```
project/
├── README.md
├── values-secrets.example.yaml   # Пример секретов (не коммитить реальные пароли)
├── helm/corp-blog/               # Helm Chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   ├── values-prod.yaml
│   └── templates/
│       ├── secret.yaml
│       ├── configmap-php.yaml
│       ├── configmap-mysql.yaml
│       ├── mysql-statefulset.yaml
│       ├── mysql-service.yaml
│       ├── wordpress-deployment.yaml
│       ├── wordpress-service.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml
│       └── pdb.yaml
├── scripts/
│   ├── setup-vm.sh
│   ├── gen-tls-cert.sh
│   ├── add-hosts.sh
│   ├── install-blog.sh
│   ├── crash-test-a-hpa.sh
│   ├── crash-test-b-drain.sh
│   └── crash-test-c-pdb.sh
├── rbac/
│   └── junior-dev.yaml
└── monitoring/
    └── install-prometheus-grafana.sh
```

---

## Definition of Done (критерии приемки)

| Критерий | Выполнение |
|----------|------------|
| В репозитории лежит Helm Chart | `helm/corp-blog/` |
| Одной командой `helm install` разворачивается весь стек | `scripts/install-blog.sh` или команда из п.3 |
| Сайт доступен по HTTPS (локальный домен) | https://blog.corp.local после настройки hosts и TLS |
| Убить любой под — сайт поднимается снова, данные не теряются | PVC у MySQL (volumeClaimTemplates), реплики WordPress |
| Вывод ноды из эксплуатации без простоя | Сценарий Б (drain), PDB (сценарий В) |
| В Grafana виден график нагрузки при стресс-тесте | Prometheus + Grafana, дашборд 6417/315 |

---

## Полезные команды

```bash
# Статус релиза
helm status corp-blog -n default

# Логи WordPress
kubectl logs -l app.kubernetes.io/component=wordpress -n default -f

# Удаление
helm uninstall corp-blog -n default
```
