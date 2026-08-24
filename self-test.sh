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
  *query1.finance.yahoo.com*|*query2.finance.yahoo.com*) exit 22 ;;
  *api.coingecko.com*)
    cat <<'JSON'
{"btc":{"usd":115000,"usd_24h_change":2.6785714286,"last_updated_at":1770000000}}
JSON
    ;;
  *stooq.com*'aapl.us'*)
    printf 'Symbol,Date,Time,Open,High,Low,Close,Volume,Prev\nAAPL.US,2026-08-24,21:00:00,220,226,219,225,1000000,220\n'
    ;;
  *stooq.com*'tsla.us'*)
    printf 'Symbol,Date,Time,Open,High,Low,Close,Volume,Prev\nTSLA.US,2026-08-24,21:00:00,333,335,328,330,1000000,333\n'
    ;;
  *) exit 22 ;;
esac
MOCK
chmod +x "$tmp/bin/curl"

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export PATH="$tmp/bin:$PATH"
mkdir -p "$HOME"

./backend.sh config | jq -e '.watchlist|length == 3' >/dev/null
quotes="$(./backend.sh quotes --force)"
jq -e '.cacheVersion == 2 and (.quotes|length == 3)' <<<"$quotes" >/dev/null
jq -e '.quotes[] | select(.symbol=="AAPL") | .provider == "Stooq" and .price == 225' <<<"$quotes" >/dev/null
jq -e '.quotes[] | select(.symbol=="TSLA") | .provider == "Stooq" and .price == 330' <<<"$quotes" >/dev/null
jq -e '.quotes[] | select(.symbol=="BTC-USD") | .provider == "CoinGecko" and .price == 115000' <<<"$quotes" >/dev/null
./backend.sh add ETH-USD Ethereum crypto >/dev/null
./backend.sh config | jq -e '.watchlist[] | select(.symbol=="ETH-USD")' >/dev/null
./backend.sh remove ETH-USD >/dev/null
! ./backend.sh config | jq -e '.watchlist[] | select(.symbol=="ETH-USD")' >/dev/null

echo "manifest: OK"
echo "backend syntax: OK"
echo "provider fallback: OK"
echo "CoinGecko crypto: OK"
echo "Stooq stock fallback: OK"
echo "watchlist CRUD: OK"
