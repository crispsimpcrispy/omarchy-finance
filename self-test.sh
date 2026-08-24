#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

jq -e . manifest.json >/dev/null
bash -n backend.sh

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.config/omarchy/finance"

cat > "$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
url="${!#}"
case "$url" in
  *api.nasdaq.com/api/quote/AAPL/info*)
    cat <<'JSON'
{"data":{"symbol":"AAPL","companyName":"Apple Inc.","primaryData":{"lastSalePrice":"$225.00","netChange":"+5.00","percentageChange":"+2.27%"}}}
JSON
    ;;
  *api.nasdaq.com/api/quote/TSLA/info*)
    cat <<'JSON'
{"data":{"symbol":"TSLA","companyName":"Tesla Inc.","primaryData":{"lastSalePrice":"$330.00","netChange":"-3.00","percentageChange":"-0.90%"}}}
JSON
    ;;
  *api.nasdaq.com/api/quote/AAPL/chart*)
    cat <<'JSON'
{"data":{"chart":[{"x":1787587200000,"y":220.0},{"x":1787590800000,"y":222.0},{"x":1787594400000,"y":225.0}]}}
JSON
    ;;
  *api.nasdaq.com/api/quote/TSLA/chart*)
    cat <<'JSON'
{"data":{"chart":[{"x":1787587200000,"y":334.0},{"x":1787590800000,"y":332.0},{"x":1787594400000,"y":330.0}]}}
JSON
    ;;
  *api.nasdaq.com/api/quote/AAPL/historical*)
    cat <<'JSON'
{"data":{"tradesTable":{"rows":[
  {"date":"08/24/2026","close":"$225.00","open":"$223.00","high":"$226.00","low":"$222.00","volume":"1,000"},
  {"date":"08/21/2026","close":"$223.00","open":"$222.00","high":"$224.00","low":"$221.00","volume":"1,000"},
  {"date":"08/20/2026","close":"$221.00","open":"$220.00","high":"$222.00","low":"$219.00","volume":"1,000"},
  {"date":"08/19/2026","close":"$220.00","open":"$218.00","high":"$221.00","low":"$217.00","volume":"1,000"}
]}}}
JSON
    ;;
  *api.nasdaq.com/api/quote/TSLA/historical*)
    cat <<'JSON'
{"data":{"tradesTable":{"rows":[
  {"date":"08/24/2026","close":"$330.00","open":"$331.00","high":"$334.00","low":"$329.00","volume":"1,000"},
  {"date":"08/21/2026","close":"$333.00","open":"$334.00","high":"$336.00","low":"$332.00","volume":"1,000"},
  {"date":"08/20/2026","close":"$335.00","open":"$336.00","high":"$337.00","low":"$334.00","volume":"1,000"},
  {"date":"08/19/2026","close":"$336.00","open":"$335.00","high":"$338.00","low":"$334.00","volume":"1,000"}
]}}}
JSON
    ;;
  *api.coingecko.com/api/v3/simple/price*bitcoin*)
    cat <<'JSON'
{"bitcoin":{"usd":115000,"usd_24h_change":2.5,"last_updated_at":1787600000}}
JSON
    ;;
  *api.coingecko.com/api/v3/coins/bitcoin/market_chart*)
    cat <<'JSON'
{"prices":[[1787241600000,108000],[1787328000000,110000],[1787414400000,112000],[1787500800000,113500],[1787587200000,115000]]}
JSON
    ;;
  *query1.finance.yahoo.com*|*query2.finance.yahoo.com*) exit 22 ;;
  *stooq.com*) exit 22 ;;
  *) echo "Unexpected URL: $url" >&2; exit 22 ;;
esac
MOCK
chmod +x "$tmp/bin/curl"

export HOME="$tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export PATH="$tmp/bin:$PATH"

cat > "$XDG_CONFIG_HOME/omarchy/finance/watchlist.json" <<'JSON'
{
  "version": 1,
  "refreshSeconds": 60,
  "watchlist": [
    {"symbol":"AAPL","name":"Apple","type":"stock"},
    {"symbol":"TSLA","name":"Tesla","type":"stock"},
    {"symbol":"BTC-USD","name":"Bitcoin","type":"crypto"}
  ]
}
JSON

cfg="$(./backend.sh config)"
jq -e '.version == 2 and .defaultRange == "1M" and (.watchlist|length == 3)' <<<"$cfg" >/dev/null
jq -e '.watchlist[] | select(.symbol=="BTC-USD") | .coinId == "bitcoin"' <<<"$cfg" >/dev/null

quotes="$(./backend.sh quotes --force)"
jq -e '.cacheVersion == 3 and (.quotes|length == 3)' <<<"$quotes" >/dev/null
jq -e '.quotes[] | select(.symbol=="AAPL") | .provider == "Nasdaq" and .price == 225 and .changePercent > 2' <<<"$quotes" >/dev/null
jq -e '.quotes[] | select(.symbol=="TSLA") | .provider == "Nasdaq" and .price == 330 and .changePercent < 0' <<<"$quotes" >/dev/null
jq -e '.quotes[] | select(.symbol=="BTC-USD") | .provider == "CoinGecko" and .price == 115000' <<<"$quotes" >/dev/null

hist_stock="$(./backend.sh history AAPL stock 1M --force)"
jq -e '.provider == "Nasdaq" and (.points|length) == 4 and .high == 225 and .low == 220' <<<"$hist_stock" >/dev/null

hist_intraday="$(./backend.sh history AAPL stock 1D --force)"
jq -e '.provider == "Nasdaq" and (.points|length) == 3 and .end == 225' <<<"$hist_intraday" >/dev/null

hist_crypto="$(./backend.sh history BTC-USD crypto 1D --force)"
jq -e '.provider == "CoinGecko" and (.points|length) == 5 and .end == 115000' <<<"$hist_crypto" >/dev/null

dashboard="$(./backend.sh dashboard --force)"
jq -e '(.assets|length)==3 and (.quotes|length)==3' <<<"$dashboard" >/dev/null
jq -e '.assets[] | select(.symbol=="AAPL") | (.sparkline|length)==4' <<<"$dashboard" >/dev/null
jq -e '.assets[] | select(.symbol=="BTC-USD") | (.sparkline|length)==5' <<<"$dashboard" >/dev/null

./backend.sh catalog | jq -e '.assets[] | select(.symbol=="RR.L")' >/dev/null
./backend.sh catalog | jq -e '.assets[] | select(.symbol=="ETH-USD" and .coinId=="ethereum")' >/dev/null

./backend.sh add ETH Ethereum crypto >/dev/null
./backend.sh config | jq -e '.watchlist[] | select(.symbol=="ETH-USD" and .coinId=="ethereum")' >/dev/null
./backend.sh remove ETH-USD >/dev/null
! ./backend.sh config | jq -e '.watchlist[] | select(.symbol=="ETH-USD")' >/dev/null

echo "manifest: OK"
echo "backend syntax: OK"
echo "v0.1 config migration: OK"
echo "Nasdaq quote + chart: OK"
echo "CoinGecko quote + chart: OK"
echo "dashboard sparklines: OK"
echo "asset catalog: OK"
echo "watchlist CRUD: OK"
