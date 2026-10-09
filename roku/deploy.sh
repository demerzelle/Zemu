#!/bin/bash
# Builds Zemu for Roku and sideloads it onto the TV's developer installer.
#
#   ./deploy.sh            build + install once
#   ./deploy.sh --watch    stay running: reinstall whenever out/deploy.request is touched,
#                          and save a screenshot to out/screenshot.jpg whenever out/screenshot.request is touched
#
# The developer password is asked once and kept only in this process's memory
# (or set ROKU_DEV_PASSWORD yourself). ROKU_IP defaults to the Westinghouse TV.
set -euo pipefail
cd "$(dirname "$0")"
ROKU_IP="${ROKU_IP:-192.168.12.105}"
if [ -z "${ROKU_DEV_PASSWORD:-}" ]; then
  read -r -s -p "Roku developer password for rokudev@$ROKU_IP: " ROKU_DEV_PASSWORD; echo
fi
mkdir -p out

build() {
  npx --prefix tools bsc --project bsconfig.json >out/bsc.log 2>&1 || { cat out/bsc.log; return 1; }
  if grep -q " error " out/bsc.log; then grep -A4 " error " out/bsc.log; return 1; fi
  rm -f out/zemu.zip
  (cd out/staging && zip -qr -9 ../zemu.zip . -x '.*')
}

install() {
  if ! build; then echo "BUILD FAILED" | tee out/deploy.result; return; fi
  local res
  res=$(curl -s -S --digest -u "rokudev:$ROKU_DEV_PASSWORD" -F "mysubmit=Install" -F "archive=@out/zemu.zip" "http://$ROKU_IP/plugin_install" 2>&1 || true)
  if echo "$res" | grep -qi "Install Success\|Identical to previous"; then
    echo "$(date +%T) installed $(du -h out/zemu.zip | cut -f1)" | tee out/deploy.result
  elif echo "$res" | grep -qi "401\|Unauthorized"; then
    echo "WRONG PASSWORD" | tee out/deploy.result
  else
    echo "$res" | sed -e 's/<[^>]*>//g' | grep -i "fail\|error\|install" | head -5 | tee out/deploy.result
  fi
}

screenshot() {
  curl -s --digest -u "rokudev:$ROKU_DEV_PASSWORD" -F "mysubmit=Screenshot" -F "passwd=" -F "archive=" "http://$ROKU_IP/plugin_inspect" >/dev/null
  curl -s --digest -u "rokudev:$ROKU_DEV_PASSWORD" -o out/screenshot.jpg "http://$ROKU_IP/pkgs/dev.jpg?time=$(date +%s)"
  echo "$(date +%T) screenshot" > out/screenshot.result
}

install
if [ "${1:-}" = "--watch" ]; then
  echo "Watching for deploy/screenshot requests (Ctrl+C to stop)…"
  touch out/deploy.request out/screenshot.request
  last_d=$(stat -f %m out/deploy.request); last_s=$(stat -f %m out/screenshot.request)
  while sleep 1; do
    d=$(stat -f %m out/deploy.request); s=$(stat -f %m out/screenshot.request)
    if [ "$d" != "$last_d" ]; then last_d=$d; install; fi
    if [ "$s" != "$last_s" ]; then last_s=$s; screenshot; fi
  done
fi
