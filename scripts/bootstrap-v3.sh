#!/bin/sh
# celld node bootstrap v3: tools + creds + systemd + tailscale mesh + reports
# Runs once at first boot on an exe.dev exeuntu VM. VM must be named celld-chat-*.
REPORT=/tmp/report.txt
POST='https://chaos-relay.com/webhook/7352ce18-82dc-4cb2-a1cf-5ca809b0b238?token=d3a92130-6bc2-45da-bf37-3f85df8ef218'
{
echo "=== bootstrap v3 $(hostname -s) $(date -u +%FT%TZ) ==="
echo "--- tools"
mkdir -p ~/.local/bin
curl -fsSL https://celld.dev/install.sh | sh >/tmp/celld-install.log 2>&1 && echo "celld OK" || echo "celld FAILED"
case $(uname -m) in x86_64|amd64) e=amd64;; aarch64|arm64) e=arm64;; esac
curl -fsSL "https://github.com/evanw/esbuild/releases/download/v0.28.2/esbuild-linux-$e-v0.28.2.tar.xz" -o /tmp/e.tar.xz
tar -xJf /tmp/e.tar.xz -C ~/.local/bin esbuild && echo "esbuild OK" || echo "esbuild FAILED"
echo "--- creds"
umask 077
cat > ~/.celld.env <<'ENVEOF'
__CREDS__
ENVEOF
umask 022
echo "--- celld unit (initial advertise: tailnet placeholder, fixed after join)"
SELF=$(hostname -s)
sudo systemctl enable --now tailscaled 2>&1
sudo tee /etc/systemd/system/celld.service >/dev/null <<UNIT
[Unit]
Description=celld node
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
User=exedev
EnvironmentFile=/home/exedev/.celld.env
Environment=CELLD_ADDR=0.0.0.0:8000
Environment=CELLD_INTERNAL_ADDR=0.0.0.0:8081
Environment=CELLD_ADVERTISE=127.0.0.1:8081
Environment=PATH=/home/exedev/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/home/exedev/.local/bin/celld
Restart=always
RestartSec=5
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now celld
sleep 10
echo "pre-join: active=$(systemctl is-active celld) health=$(curl -s --max-time 5 http://127.0.0.1:8000/.well-known/celld/health)"
} > "$REPORT" 2>&1
curl -s --max-time 20 -X POST -H 'content-type: text/plain' --data-binary @"$REPORT" "$POST"

# --- tailscale join (non-blocking; auth URL posted for human click) ---
(
  TSOUT=$(sudo tailscale up --timeout=10m 2>&1)
  echo "=== tailscale $(hostname -s) $(date -u +%FT%TZ) ===" > /tmp/ts-report.txt
  echo "$TSOUT" >> /tmp/ts-report.txt
  TSIP=$(tailscale ip -4 2>/dev/null)
  echo "ts-ip: $TSIP" >> /tmp/ts-report.txt
  if [ -n "$TSIP" ]; then
    sudo sed -i "s|^Environment=CELLD_INTERNAL_ADDR=.*|Environment=CELLD_INTERNAL_ADDR=$TSIP:8081|; s|^Environment=CELLD_ADVERTISE=.*|Environment=CELLD_ADVERTISE=$TSIP:8081|" /etc/systemd/system/celld.service
    sudo systemctl daemon-reload
    sudo systemctl restart celld
    sleep 10
    echo "post-join: active=$(systemctl is-active celld) health=$(curl -s --max-time 5 http://127.0.0.1:8000/.well-known/celld/health)" >> /tmp/ts-report.txt
    echo "advertise line: $(grep CELLD_ADVERTISE /etc/systemd/system/celld.service)" >> /tmp/ts-report.txt
  fi
  curl -s --max-time 20 -X POST -H 'content-type: text/plain' --data-binary @/tmp/ts-report.txt "$POST"
) &
