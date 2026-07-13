#!/usr/bin/env bash
set -euo pipefail

umask 022

ssh_port=${SYNOLOGY_DEV_SSH_PORT:-2222}
fail2ban_maxretry=${SYNOLOGY_DEV_FAIL2BAN_MAXRETRY:-3}
fail2ban_findtime=${SYNOLOGY_DEV_FAIL2BAN_FINDTIME:-10m}
fail2ban_bantime=${SYNOLOGY_DEV_FAIL2BAN_BANTIME:-10m}

for state_dir in \
  /home/esko/.cache \
  /home/esko/.config \
  /home/esko/.local \
  /home/esko/.local/share \
  /home/esko/.local/state; do
  mkdir -p "$state_dir"
  chown 1026:100 "$state_dir"
  chmod u+rwx "$state_dir"
done

mkdir -p \
  /var/empty/sshd \
  /run/sshd \
  /etc/ssh \
  /var/log \
  /var/lib/fail2ban \
  /var/run/fail2ban
chmod 711 /var/empty/sshd
: > /var/log/sshd.log
chmod 644 /var/log/sshd.log

ssh-keygen -A >/dev/null

cat >/etc/ssh/sshd_config <<EOF
Port ${ssh_port}
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers esko
AuthorizedKeysFile .ssh/authorized_keys
LogLevel VERBOSE
EOF

# Mirror NixOS fail2ban defaults, but use polling because the container has no
# systemd journal. See nixos/modules/services/security/fail2ban.nix.
cat >/etc/fail2ban/jail.d/synology-dev.local <<EOF
[INCLUDES]
before = paths-synology-dev.conf

[DEFAULT]
backend = polling
banaction = iptables-multiport
banaction_allports = iptables-allports
ignoreip = 127.0.0.1/8 ::1
maxretry = ${fail2ban_maxretry}
bantime = ${fail2ban_bantime}
findtime = ${fail2ban_findtime}

[sshd]
enabled = true
port = ${ssh_port}
logpath = /var/log/sshd.log
EOF

if command -v fail2ban-server >/dev/null 2>&1; then
  fail2ban-server -xb
  fail2ban-client status sshd >/dev/null
else
  printf '%s\n' 'fail2ban-server is not available; continuing without intrusion blocking' >&2
fi

# Prefix sshd -e output so the upstream sshd filter can parse it.
/bin/sshd -D -e -p "$ssh_port" 2>&1 | while IFS= read -r line; do
  printf '%s %s sshd[1]: %s\n' "$(date '+%b %d %T')" "$(hostname)" "$line" >>/var/log/sshd.log
done
