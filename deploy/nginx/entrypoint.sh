#!/bin/sh
# gsc-hub: nginx с автоматическим включением HTTPS.
#
# Пока сертификата нет — работает только http.conf (:80, приложение доступно
# по http). Как только certbot положил сертификат в
# /etc/letsencrypt/live/$HTTPS_DOMAIN, здесь же включается блок 443
# (tls.conf) и редирект с 80 (redirect.conf). Сертификат в /etc/nginx/tls
# подставляется симлинками, поэтому его продление certbot'ом подхватывается
# без каких-либо действий: фоновый цикл замечает изменение файла
# и делает nginx -s reload.
#
# HTTPS_DOMAIN не задан — работаем как чистый HTTP-nginx.

GSC=/etc/nginx/gsc
CONF=/etc/nginx/conf.d
LE=/etc/letsencrypt/live
TLS_DIR=/etc/nginx/tls
DOMAIN="${HTTPS_DOMAIN:-}"

# changed=1, если sync_conf что-то переписал (включил/выключил TLS).
changed=0

tls_ready() {
    [ -n "$DOMAIN" ] &&
        [ -f "$LE/$DOMAIN/fullchain.pem" ] &&
        [ -f "$LE/$DOMAIN/privkey.pem" ]
}

copy_if_diff() {
    if ! cmp -s "$1" "$2" 2>/dev/null; then
        cp "$1" "$2"
        changed=1
    fi
}

remove_if_exists() {
    if [ -e "$1" ]; then
        rm -f "$1"
        changed=1
    fi
}

link_if_diff() {
    if [ "$(readlink "$2" 2>/dev/null)" != "$1" ]; then
        ln -sfn "$1" "$2"
    fi
}

sync_conf() {
    changed=0
    if tls_ready; then
        mkdir -p "$TLS_DIR"
        link_if_diff "$LE/$DOMAIN/fullchain.pem" "$TLS_DIR/fullchain.pem"
        link_if_diff "$LE/$DOMAIN/privkey.pem" "$TLS_DIR/privkey.pem"
        copy_if_diff "$GSC/tls.conf" "$CONF/zz-tls.conf"
        sed "s/__DOMAIN__/$DOMAIN/g" "$GSC/redirect.conf" > /tmp/redirect.conf
        copy_if_diff /tmp/redirect.conf "$CONF/zz-redirect.conf"
    else
        remove_if_exists "$CONF/zz-tls.conf"
        remove_if_exists "$CONF/zz-redirect.conf"
    fi
}

# cksum, а не stat: у certbot'а сертификат — цепочка симлинков, а cksum
# их честно разворачивает; сравниваем контрольную сумму, чтобы заметить
# продление и перезагрузить nginx.
cert_sum() {
    cksum "$LE/$DOMAIN/fullchain.pem" 2>/dev/null || echo none
}

# HTTP-конфиг всегда: он же отдаёт файлы вызова ACME до выпуска сертификата.
cp "$GSC/http.conf" "$CONF/default.conf"
sync_conf

# Фоновый надзор: включение/выключение TLS и перезапуск после продления.
(
    last=$(cert_sum)
    pending=0
    while :; do
        sleep 15
        sync_conf
        now=$(cert_sum)
        if [ "$changed" = 1 ] || [ "$now" != "$last" ]; then
            pending=1
        fi
        # reload может не получиться, пока nginx ещё стартует, — тогда
        # оставляем pending и пробуем на следующем круге.
        if [ "$pending" = 1 ] && nginx -s reload 2>/dev/null; then
            echo "gsc-tls: конфигурация или сертификат изменились — reload"
            last=$now
            pending=0
        fi
    done
) &

exec /docker-entrypoint.sh nginx -g 'daemon off;'
