#!/bin/bash
# Создаёт самоподписанный сертификат для подписи Nook.
#
# Зачем: ad-hoc подпись меняет хеш кода при каждой сборке, а macOS привязывает
# выданные разрешения (Календарь, Напоминания, Универсальный доступ) именно
# к подписи. Без стабильного сертификата система переспрашивала бы доступ
# после каждой пересборки.
#
# С этим сертификатом требование к подписи выглядит так:
#   identifier "com.trunook.Nook" and certificate root = H"..."
# Хеша кода в нём нет, поэтому разрешения переживают пересборку.
#
# Запускается один раз: make cert

set -euo pipefail

NAME="${1:-Trunook Dev Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Сертификат «$NAME» уже существует и пригоден для подписи."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Создаю ключ и сертификат…"
openssl req -x509 -newkey rsa:2048 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -nodes \
    -subj "/CN=$NAME/O=Nook" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    2>/dev/null

openssl pkcs12 -export -legacy \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" -passout pass:nook -name "$NAME" \
    2>/dev/null

echo "Импортирую в связку ключей…"
# -A разрешает доступ к ключу всем программам: иначе codesign при каждой
# сборке спрашивал бы пароль от связки ключей.
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P nook -A \
    -T /usr/bin/codesign -T /usr/bin/security

echo "Отмечаю сертификат как доверенный для подписи кода…"
# Без явного доверия codesign отказывается его использовать
# (CSSMERR_TP_NOT_TRUSTED). Доверие ограничено ролью codeSign.
security add-trusted-cert -r trustRoot -p codeSign "$WORK/cert.pem"

echo
security find-identity -v -p codesigning
echo
echo "Готово. Теперь работает: make install"
