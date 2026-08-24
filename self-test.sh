#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

jq -e . manifest.json >/dev/null
bash -n backend.sh

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
url="${@: -1}"
case "$url" in
  *AAPL*) price=225; prev=220; symbol=AAPL; instrument=EQUITY ;;
  *TSLA*) price=330; prev=333; symbol=TSLA; instrument=EQUITY ;;
  *BTC-USD*) price=115000; prev=112000; symbol=BTC-USD; instrument=CRYPTOCURRENCY ;;
  *) exit 22 ;;
esac
cat <<JSON
{"chart":{"result":[{"meta":{"currency":"USD","symbol":"$symbol","exchangeName":"TEST","instrumentType":"$instrument","regularMarketPrice":$price,"previousClose":$prev,"regularMarketTime":1770000000},"indicators":{"quote":[{"close":[$price]}]}}],"error":null}}
JSON
MOCK
chmod +x "$tmp/bin/curl"

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export PATH="$tmp/bin:$PATH"
mkdir -p "$HOME"

./backend.sh config | jq -e '.watchlist|length == 3' >/dev/null
./backend.sh quotes --force | jq -e '.quotes|length == 3' >/dev/null
./backend.sh quotes | jq -e '.quotes[] | select(.symbol=="AAPL") | .changePercent > 2' >/dev/null
./backend.sh add ETH-USD Ethereum crypto >/dev/null
./backend.sh config | jq -e '.watchlist[] | select(.symbol=="ETH-USD")' >/dev/null
./backend.sh remove ETH-USD >/dev/null
! ./backend.sh config | jq -e '.watchlist[] | select(.symbol=="ETH-USD")' >/dev/null

echo "manifest: OK"
echo "backend syntax: OK"
echo "watchlist CRUD: OK"
echo "quote parsing/cache: OK"
