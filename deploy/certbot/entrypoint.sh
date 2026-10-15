#!/bin/sh
# gsc-hub: выпуск и продление сертификата Let's Encrypt (HTTP-01, webroot).
#
# Вызов ACME отдаёт nginx из /var/www/certbot, поэтому порт 80 должен быть
# доступен из интернета, а HTTPS_DOMAIN — указывать на этот сервер.
# Первый выпуск повторяется каждую минуту, пока не получится (nginx может
# подниматься дольше); продление — раз в 12 часов.

DOMAIN="${HTTPS_DOMAIN:-}"
EMAIL="${LETSENCRYPT_EMAIL:-}"
WEBROOT=/var/www/certbot
LIVE="/etc/letsencrypt/live/$DOMAIN"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "certbot: задайте HTTPS_DOMAIN и LETSENCRYPT_EMAIL в .env — сплю" >&2
    exec sleep infinity
fi

issue() {
    certbot certonly --webroot -w "$WEBROOT" -d "$DOMAIN" \
        --non-interactive --agree-tos --email "$EMAIL" \
        --keep-until-expiring
}

while :; do
    if [ ! -f "$LIVE/fullchain.pem" ]; then
        echo "certbot: сертификата для $DOMAIN нет — пробую получить"
        issue || echo "certbot: не получилось, повтор через минуту" >&2
        sleep 60
    else
        certbot renew --quiet || true
        sleep 12h
    fi
done
