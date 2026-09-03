#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: executar com sudo:"
    echo "sudo $0 /caminho/backup-canais-COMPLETO.tar.gz"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${1:-}" ]; then
    BACKUP="$1"
else
    BACKUP="$(ls -1t "$SCRIPT_DIR"/backup-canais-FINAL-LITE-*.tar.gz 2>/dev/null | head -n 1)"
fi

if [ -z "$BACKUP" ] || [ ! -f "$BACKUP" ]; then
    echo "ERRO: backup-canais-FINAL-LITE-*.tar.gz nao encontrado."
    echo "Coloca o backup na mesma pasta deste instalador."
    exit 1
fi

echo "Backup encontrado: $BACKUP"

echo "=== INSTALAR DEPENDENCIAS ==="
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
    nginx \
    apache2-utils \
    python3 \
    python3-flask \
    openssh-client \
    openvpn \
    acl \
    rsync \
    git \
    imagemagick \
    librsvg2-bin \
    curl \
    wget \
    tar \
    gzip

echo
echo "=== PARAR SERVICOS ==="
systemctl stop canais-auto.timer 2>/dev/null || true
systemctl stop canais-painel 2>/dev/null || true
systemctl stop nginx 2>/dev/null || true

echo
echo "=== RESTAURAR BACKUP ==="
tar -xzf "$BACKUP" -C /

echo
echo
echo "=== OBTER BASE DE PICONS ==="
/usr/local/bin/atualizar-base-picons.sh
[ -d /home/ubuntu/picons ] && chown -R ubuntu:ubuntu /home/ubuntu/picons

echo "=== PERMISSOES ==="
chmod +x /usr/local/bin/sincronizar-box.sh 2>/dev/null || true
chmod +x /usr/local/bin/atualizar-canais.sh 2>/dev/null || true
chmod +x /usr/local/bin/atualizar-clientes.py 2>/dev/null || true
chmod +x /usr/local/bin/criar-picons-cabo.py 2>/dev/null || true
chmod +x /usr/local/bin/atualizar-base-picons.sh 2>/dev/null || true
chmod +x /usr/local/sbin/canais-auto-config 2>/dev/null || true

chown -R ubuntu:ubuntu /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
find /home/ubuntu/.ssh -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
find /home/ubuntu/.ssh -type f -name "*.pub" -exec chmod 644 {} \;
[ -f /home/ubuntu/.ssh/known_hosts ] && chmod 644 /home/ubuntu/.ssh/known_hosts

echo
echo
echo "=== PERMISSOES VPN CLIENTE ==="
mkdir -p /etc/openvpn/client
setfacl -m u:ubuntu:rwx /etc/openvpn/client
[ -f /etc/openvpn/client/canais.conf ] && setfacl -m u:ubuntu:rw /etc/openvpn/client/canais.conf

echo "=== SYSTEMD ==="
systemctl daemon-reload

# VPN cliente canais: restaurada mas fica DESLIGADA por defeito
systemctl disable --now openvpn-client@canais.service 2>/dev/null || true

systemctl enable canais-painel.service
systemctl enable canais-auto.timer
systemctl enable nginx

echo
echo
echo "=== PASSWORD DO PAINEL ==="
while true; do
    read -s -p "Nova password do painel: " PAINEL_PASS
    echo
    read -s -p "Repita a password: " PAINEL_PASS2
    echo
    [ -n "$PAINEL_PASS" ] && [ "$PAINEL_PASS" = "$PAINEL_PASS2" ] && break
    echo "Passwords diferentes ou vazias. Tente novamente."
done

htpasswd -bc /etc/nginx/.htpasswd-canais admin "$PAINEL_PASS"
unset PAINEL_PASS PAINEL_PASS2

if ! grep -q 'auth_basic "Painel Canais"' /etc/nginx/sites-available/canais; then
    sed -i '/location \/painel\/ {/a\        auth_basic "Painel Canais";\n        auth_basic_user_file /etc/nginx/.htpasswd-canais;' /etc/nginx/sites-available/canais
fi

echo "=== TESTAR NGINX ==="
rm -f /etc/nginx/sites-enabled/default
nginx -t

echo
echo "=== ARRANCAR ==="
systemctl restart nginx
systemctl restart canais-painel
systemctl restart canais-auto.timer

echo
echo "=== ESTADO ==="
echo -n "Painel: "
systemctl is-active canais-painel

echo -n "NGINX: "
systemctl is-active nginx

echo -n "Timer: "
systemctl is-active canais-auto.timer

echo
systemctl list-timers canais-auto.timer --no-pager

echo
echo "======================================"
echo " RESTAURO CONCLUIDO"
echo "======================================"
echo
echo "Antes de atualizar canais confirma:"
echo "1. VPN desta VPS ligada"
echo "2. IP da Box Mestre correto em /srv/canais/config.json"
echo "3. SSH para a Box Mestre funcional"
