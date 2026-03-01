# Корпоративный блог (On-Prem Simulation)

Отказоустойчивый внутренний блог: Kubernetes, Helm, WordPress, MySQL, Prometheus/Grafana, TLS.

**Сервер:** Ubuntu 24.04.4 LTS, IP 192.168.1.31 (bridge).

---

## Быстрый старт (одна команда после подготовки)

После выполнения [Подготовка VM](#1-подготовка-vm) и создания TLS-сертификата:

```bash
cd /path/to/555
export MYSQL_ROOT_PASSWORD='SecureRootPass1' MYSQL_PASSWORD='WpUserPass1'
bash scripts/install-blog.sh default
```

Сайт: **https://blog.corp.local** (добавить в hosts на ПК, с которого заходите в браузер).

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

### 2. TLS-сертификат для blog.corp.local

На сервере (или локально, затем скопировать файлы):

```bash
cd /path/to/555
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
  --wait --timeout 5m
```

**Prod** (3 реплики WordPress, HPA):

```bash
helm upgrade --install corp-blog ./helm/corp-blog \
  -n default \
  -f helm/corp-blog/values.yaml \
  -f helm/corp-blog/values-prod.yaml \
  --set mysqlRootPassword="$MYSQL_ROOT_PASSWORD" \
  --set mysqlPassword="$MYSQL_PASSWORD" \
  --wait --timeout 5m
```

Проверка: поды и сервисы в состоянии Running.

### 4. Доступ по домену и HTTPS

- **Minikube:** Ingress Controller получает трафик через внутренний IP Minikube. Чтобы заходить с вашего ПК по домену:
  - Вариант А: на **вашем ПК** (Windows) добавить в `C:\Windows\System32\drivers\etc\hosts` строку:
    - Сначала узнать IP: на VM выполнить `minikube ip`.
    - Если браузер открываете с той же VM — использовать этот IP.
    - Если браузер с домашнего ПК — нужен доступ к кластеру: либо проброс портов, либо настроить Ingress на 192.168.1.31 (см. ниже).
  - Вариант Б (проще для теста с ПК): порт-форвард на VM:
    - На VM: `kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 443:443 &`
    - На ПК в hosts: `192.168.1.31 blog.corp.local`
    - Открыть https://blog.corp.local (предупреждение о сертификате — принять).

- Или на ПК в **hosts** добавить (от имени администратора):
  - `192.168.1.31 blog.corp.local` — если Ingress слушает на 192.168.1.31 (например, через tunnel или настройку сети).

Скрипт-подсказка (на машине, где правите hosts):

```bash
# Linux/Mac:
sudo bash scripts/add-hosts.sh 192.168.1.31
```

Откройте в браузере: **https://blog.corp.local**. Должно открыться с предупреждением о самоподписанном сертификате — это ожидаемо.

### 5. Мониторинг (Prometheus + Grafana)

```bash
bash monitoring/install-prometheus-grafana.sh monitoring
```

Доступ к Grafana:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80
```

Браузер: http://localhost:3000 — логин **admin**, пароль **admin**.

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

- Установить чарт в prod-режиме (HPA включён). Запустить нагрузку и смотреть рост подов:

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
555/
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
