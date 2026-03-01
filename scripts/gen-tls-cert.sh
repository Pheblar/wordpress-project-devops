#!/bin/bash
# Генерация самоподписанного сертификата для blog.corp.local
# Результат: tls.crt, tls.key в текущей директории (или в указанной)

OUT_DIR="${1:-.}"
mkdir -p "$OUT_DIR"
cd "$OUT_DIR"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=blog.corp.local/O=Corp Blog" \
  -addext "subjectAltName=DNS:blog.corp.local"

echo "Сертификат создан: $OUT_DIR/tls.crt, $OUT_DIR/tls.key"
echo "Для Helm: закодируйте в base64 и укажите в values или создайте Secret:"
echo "  kubectl create secret tls blog-corp-tls --cert=tls.crt --key=tls.key -n <namespace>"
