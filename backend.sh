#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="io.github.crispsimpcrispy.finance"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="$CONFIG_HOME/omarchy/finance"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-finance"
HISTORY_DIR="$CACHE_DIR/history"
CONFIG_FILE="$STATE_DIR/watchlist.json"
QUOTE_CACHE="$CACHE_DIR/quotes.json"
CACHE_VERSION=3
CONFIG_VERSION=2

mkdir -p "$STATE_DIR" "$CACHE_DIR" "$HISTORY_DIR"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }

seed_config() {
  [[ -f "$CONFIG_FILE" ]] && return 0
  cat > "$CONFIG_FILE" <<'JSON'
{
  "version": 2,
  "refreshSeconds": 60,
  "barRotateSeconds": 5,
  "defaultRange": "1M",
  "watchlist": [
    {"symbol":"AAPL","name":"Apple","type":"stock","assetClass":"stocks","coinId":""},
    {"symbol":"TSLA","name":"Tesla","type":"stock","assetClass":"stocks","coinId":""},
    {"symbol":"BTC-USD","name":"Bitcoin","type":"crypto","assetClass":"crypto","coinId":"bitcoin"}
  ]
}
JSON
}

atomic_jq() {
  local filter="$1"; shift
  local tmp
  tmp="$(mktemp "$STATE_DIR/.watchlist.XXXXXX")"
  if jq "$@" "$filter" "$CONFIG_FILE" > "$tmp"; then
    mv "$tmp" "$CONFIG_FILE"
  else
    rm -f "$tmp"
    return 1
  fi
}

coin_id_for_symbol() {
  local base="${1^^}"
  base="${base%%-*}"
  case "$base" in
    BTC) printf 'bitcoin' ;;
    ETH) printf 'ethereum' ;;
    SOL) printf 'solana' ;;
    XRP) printf 'ripple' ;;
    ADA) printf 'cardano' ;;
    DOGE) printf 'dogecoin' ;;
    AVAX) printf 'avalanche-2' ;;
    DOT) printf 'polkadot' ;;
    LINK) printf 'chainlink' ;;
    LTC) printf 'litecoin' ;;
    BCH) printf 'bitcoin-cash' ;;
    XLM) printf 'stellar' ;;
    *) printf '%s' "${base,,}" ;;
  esac
}

migrate_config() {
  seed_config
  local version
  version="$(jq -r '.version // 1' "$CONFIG_FILE" 2>/dev/null || echo 1)"
  if [[ "$version" -lt 2 ]]; then
    atomic_jq '
      .version=2
      | .barRotateSeconds=(.barRotateSeconds // 5)
      | .defaultRange=(.defaultRange // "1M")
      | .watchlist |= map(
          .assetClass=(.assetClass // (if (.type // "stock") == "crypto" then "crypto" else "stocks" end))
          | .coinId=(.coinId // (if .symbol == "BTC-USD" then "bitcoin" elif .symbol == "ETH-USD" then "ethereum" elif .symbol == "SOL-USD" then "solana" else "" end))
        )
    '
  fi
  atomic_jq '
    .version=2
    | .refreshSeconds=(.refreshSeconds // 60)
    | .barRotateSeconds=(.barRotateSeconds // 5)
    | .defaultRange=(.defaultRange // "1M")
    | .watchlist |= map(
        .type=(.type // "stock")
        | .assetClass=(.assetClass // (if (.type // "stock") == "crypto" then "crypto" else "stocks" end))
        | .coinId=(.coinId // "")
      )
  '
}

config() { migrate_config; cat "$CONFIG_FILE"; }

normalize_symbol() {
  local s="${1:-}"
  s="${s//[[:space:]]/}"
  printf '%s' "${s^^}"
}

add_asset() {
  migrate_config; require_cmd jq
  local symbol name type coin_id asset_class
  symbol="$(normalize_symbol "${1:-}")"
  name="${2:-}"
  type="${3:-stock}"
  coin_id="${4:-}"
  asset_class="${5:-}"
  [[ -n "$symbol" ]] || fail "Symbol cannot be empty"
  [[ "$type" == "stock" || "$type" == "crypto" ]] || type="stock"
  [[ -n "$name" ]] || name="$symbol"
  if [[ "$type" == "crypto" ]]; then
    [[ "$symbol" == *-* ]] || symbol="${symbol}-USD"
    [[ -n "$coin_id" ]] || coin_id="$(coin_id_for_symbol "$symbol")"
    [[ -n "$asset_class" ]] || asset_class="crypto"
  else
    [[ -n "$asset_class" ]] || asset_class="stocks"
  fi
  if jq -e --arg s "$symbol" '.watchlist[]? | select((.symbol|ascii_upcase)==$s)' "$CONFIG_FILE" >/dev/null; then
    fail "$symbol is already on the watchlist"
  fi
  atomic_jq '.watchlist += [{symbol:$symbol,name:$name,type:$type,coinId:$coinId,assetClass:$assetClass}]' \
    --arg symbol "$symbol" --arg name "$name" --arg type "$type" --arg coinId "$coin_id" --arg assetClass "$asset_class"
  rm -f "$QUOTE_CACHE"
  rm -f "$HISTORY_DIR"/* 2>/dev/null || true
  printf 'Added %s.\n' "$symbol"
}

remove_asset() {
  migrate_config
  local symbol
  symbol="$(normalize_symbol "${1:-}")"
  [[ -n "$symbol" ]] || fail "Symbol cannot be empty"
  atomic_jq '.watchlist |= map(select((.symbol|ascii_upcase)!=$symbol))' --arg symbol "$symbol"
  rm -f "$QUOTE_CACHE"
  rm -f "$HISTORY_DIR"/* 2>/dev/null || true
  printf 'Removed %s.\n' "$symbol"
}

catalog() {
  cat <<'JSON'
{
  "assets": [
    {"symbol":"AAPL","name":"Apple","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"TSLA","name":"Tesla","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"NVDA","name":"NVIDIA","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"MSFT","name":"Microsoft","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"AMZN","name":"Amazon","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"GOOGL","name":"Alphabet","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"META","name":"Meta Platforms","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"AMD","name":"AMD","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"NFLX","name":"Netflix","type":"stock","assetClass":"stocks","coinId":"","market":"NASDAQ"},
    {"symbol":"SPY","name":"S&P 500 ETF","type":"stock","assetClass":"etf","coinId":"","market":"NYSE Arca"},
    {"symbol":"QQQ","name":"Nasdaq 100 ETF","type":"stock","assetClass":"etf","coinId":"","market":"NASDAQ"},
    {"symbol":"RR.L","name":"Rolls-Royce Holdings","type":"stock","assetClass":"stocks","coinId":"","market":"LSE"},
    {"symbol":"BA.L","name":"BAE Systems","type":"stock","assetClass":"stocks","coinId":"","market":"LSE"},
    {"symbol":"SHEL.L","name":"Shell","type":"stock","assetClass":"stocks","coinId":"","market":"LSE"},
    {"symbol":"AZN.L","name":"AstraZeneca","type":"stock","assetClass":"stocks","coinId":"","market":"LSE"},
    {"symbol":"LLOY.L","name":"Lloyds Banking Group","type":"stock","assetClass":"stocks","coinId":"","market":"LSE"},
    {"symbol":"VOD.L","name":"Vodafone","type":"stock","assetClass":"stocks","coinId":"","market":"LSE"},
    {"symbol":"BTC-USD","name":"Bitcoin","type":"crypto","assetClass":"crypto","coinId":"bitcoin","market":"Crypto"},
    {"symbol":"ETH-USD","name":"Ethereum","type":"crypto","assetClass":"crypto","coinId":"ethereum","market":"Crypto"},
    {"symbol":"SOL-USD","name":"Solana","type":"crypto","assetClass":"crypto","coinId":"solana","market":"Crypto"},
    {"symbol":"XRP-USD","name":"XRP","type":"crypto","assetClass":"crypto","coinId":"ripple","market":"Crypto"},
    {"symbol":"ADA-USD","name":"Cardano","type":"crypto","assetClass":"crypto","coinId":"cardano","market":"Crypto"},
    {"symbol":"DOGE-USD","name":"Dogecoin","type":"crypto","assetClass":"crypto","coinId":"dogecoin","market":"Crypto"},
    {"symbol":"LINK-USD","name":"Chainlink","type":"crypto","assetClass":"crypto","coinId":"chainlink","market":"Crypto"}
  ]
}
JSON
}

cache_is_fresh() {
  local file="$1" ttl="$2" now modified
  [[ -f "$file" ]] || return 1
  now="$(date +%s)"
  modified="$(stat -c %Y "$file" 2>/dev/null || echo 0)"
  (( now - modified < ttl ))
}

number_clean() {
  local value="${1:-}"
  value="${value//\$/}"
  value="${value//£/}"
  value="${value//€/}"
  value="${value//,/}"
  value="${value//%/}"
  value="${value//+/}"
  value="${value// /}"
  [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]] || return 1
  printf '%s' "$value"
}

format_price() {
  local price="$1" currency="$2"
  awk -v p="$price" -v c="$currency" 'BEGIN {
    ap=(p<0?-p:p); decimals=(ap<1 ? 4 : 2);
    if (c=="USD") s="$"; else if (c=="GBP") s="£"; else if (c=="EUR") s="€"; else s="";
    printf "%s%.*f", s, decimals, p;
  }'
}

quote_from_change() {
  local symbol="$1" name="$2" type="$3" currency="$4" exchange="$5" instrument="$6" price="$7" change="$8" pct="$9" market_time="${10}" provider="${11}"
  local previous formatted
  previous="$(awk -v p="$price" -v c="$change" 'BEGIN{printf "%.10f", p-c}')"
  formatted="$(format_price "$price" "$currency")"
  jq -nc \
    --arg symbol "$symbol" --arg name "$name" --arg type "$type" \
    --arg currency "$currency" --arg exchange "$exchange" --arg instrumentType "$instrument" \
    --arg priceFormatted "$formatted" --arg provider "$provider" \
    --argjson price "$price" --argjson previousClose "$previous" \
    --argjson change "$change" --argjson changePercent "$pct" --argjson marketTime "${market_time:-0}" \
    '{symbol:$symbol,name:$name,type:$type,currency:$currency,exchange:$exchange,instrumentType:$instrumentType,provider:$provider,price:$price,priceFormatted:$priceFormatted,previousClose:$previousClose,change:$change,changePercent:$changePercent,marketTime:$marketTime}'
}

quote_from_previous() {
  local symbol="$1" name="$2" type="$3" currency="$4" exchange="$5" instrument="$6" price="$7" previous="$8" market_time="$9" provider="${10}"
  local change pct
  if [[ -n "$previous" && "$previous" != "0" ]] && awk -v p="$previous" 'BEGIN{exit !(p!=0)}'; then
    change="$(awk -v p="$price" -v prev="$previous" 'BEGIN{printf "%.10f", p-prev}')"
    pct="$(awk -v p="$price" -v prev="$previous" 'BEGIN{printf "%.10f", ((p-prev)/prev)*100}')"
  else
    change=0; pct=0
  fi
  quote_from_change "$symbol" "$name" "$type" "$currency" "$exchange" "$instrument" "$price" "$change" "$pct" "$market_time" "$provider"
}

nasdaq_headers() {
  printf '%s\n' \
    '-H' 'accept: application/json, text/plain, */*' \
    '-H' 'accept-language: en-US,en;q=0.9' \
    '-H' 'origin: https://www.nasdaq.com' \
    '-H' 'referer: https://www.nasdaq.com/' \
    '-A' 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/151 Safari/537.36'
}

fetch_nasdaq_quote() {
  local symbol="$1" name="$2" type="$3" asset_class="$4" raw data primary price change pct currency market_time
  [[ "$symbol" != *.* && "$symbol" != *-* ]] || return 1
  mapfile -t hdr < <(nasdaq_headers)
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 "${hdr[@]}" \
    "https://api.nasdaq.com/api/quote/${symbol}/info?assetclass=${asset_class:-stocks}" 2>/dev/null)" || return 1
  data="$(jq -c '.data // empty' <<<"$raw" 2>/dev/null || true)"
  [[ -n "$data" && "$data" != "null" ]] || return 1
  primary="$(jq -c '.primaryData // {}' <<<"$data")"
  price="$(number_clean "$(jq -r '.lastSalePrice // empty' <<<"$primary")" 2>/dev/null || true)"
  [[ -n "$price" ]] || return 1
  change="$(number_clean "$(jq -r '.netChange // "0"' <<<"$primary")" 2>/dev/null || echo 0)"
  pct="$(number_clean "$(jq -r '.percentageChange // "0"' <<<"$primary")" 2>/dev/null || echo 0)"
  currency="USD"
  market_time=0
  quote_from_change "$symbol" "$name" "$type" "$currency" "NASDAQ" "EQUITY" "$price" "${change:-0}" "${pct:-0}" "$market_time" "Nasdaq"
}

fetch_yahoo_quote() {
  local symbol="$1" name="$2" type="$3" host="${4:-query1.finance.yahoo.com}" encoded raw result meta price previous currency exchange instrument market_time
  encoded="$(jq -rn --arg v "$symbol" '$v|@uri')"
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
    -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/151 Safari/537.36' \
    "https://${host}/v8/finance/chart/${encoded}?range=1d&interval=5m" 2>/dev/null)" || return 1
  result="$(jq -c '.chart.result[0] // empty' <<<"$raw" 2>/dev/null || true)"
  [[ -n "$result" ]] || return 1
  meta="$(jq -c '.meta // {}' <<<"$result")"
  price="$(jq -r '.regularMarketPrice // empty' <<<"$meta")"
  [[ -n "$price" && "$price" != "null" ]] || price="$(jq -r '[.indicators.quote[0].close[]? | select(. != null)] | last // empty' <<<"$result")"
  [[ -n "$price" && "$price" != "null" ]] || return 1
  previous="$(jq -r '.previousClose // .chartPreviousClose // 0' <<<"$meta")"
  currency="$(jq -r '.currency // "USD"' <<<"$meta")"
  exchange="$(jq -r '.exchangeName // "Yahoo"' <<<"$meta")"
  instrument="$(jq -r '.instrumentType // ""' <<<"$meta")"
  market_time="$(jq -r '.regularMarketTime // 0' <<<"$meta")"
  quote_from_previous "$symbol" "$name" "$type" "$currency" "$exchange" "$instrument" "$price" "$previous" "$market_time" "Yahoo Finance"
}

stooq_symbol() {
  local s="${1^^}"
  case "$s" in
    *.L) printf '%s.uk' "${s%.L}" | tr '[:upper:]' '[:lower:]' ;;
    *.DE) printf '%s.de' "${s%.DE}" | tr '[:upper:]' '[:lower:]' ;;
    *.UK|*.US) printf '%s' "$s" | tr '[:upper:]' '[:lower:]' ;;
    *.*) printf '%s' "$s" | tr '[:upper:]' '[:lower:]' ;;
    *) printf '%s.us' "$s" | tr '[:upper:]' '[:lower:]' ;;
  esac
}

fetch_stooq_quote() {
  local symbol="$1" name="$2" type="$3" ss raw line sdate stime open high low close volume previous currency
  ss="$(stooq_symbol "$symbol")"
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
    -A 'Mozilla/5.0 (X11; Linux x86_64)' \
    "https://stooq.com/q/l/?s=${ss}&f=sd2t2ohlcvp&h&e=csv" 2>/dev/null)" || return 1
  line="$(printf '%s\n' "$raw" | tail -n1 | tr -d '\r')"
  [[ -n "$line" && "$line" != Symbol,* ]] || return 1
  IFS=',' read -r _ sdate stime open high low close volume previous <<<"$line"
  [[ -n "$close" && "$close" != "N/D" ]] || return 1
  [[ -n "$previous" && "$previous" != "N/D" ]] || previous="$open"
  currency="USD"; [[ "$symbol" == *.L ]] && currency="GBP"
  quote_from_previous "$symbol" "$name" "$type" "$currency" "Stooq" "EQUITY" "$close" "${previous:-0}" 0 "Stooq"
}

fetch_coingecko_quote() {
  local symbol="$1" name="$2" coin_id="$3" raw price pct market_time previous
  [[ -n "$coin_id" ]] || coin_id="$(coin_id_for_symbol "$symbol")"
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
    -H 'accept: application/json' -A 'omarchy-finance/0.2.0' \
    "https://api.coingecko.com/api/v3/simple/price?ids=${coin_id}&vs_currencies=usd&include_24hr_change=true&include_last_updated_at=true" 2>/dev/null)" || return 1
  price="$(jq -r --arg k "$coin_id" '.[$k].usd // empty' <<<"$raw" 2>/dev/null || true)"
  pct="$(jq -r --arg k "$coin_id" '.[$k].usd_24h_change // 0' <<<"$raw" 2>/dev/null || echo 0)"
  market_time="$(jq -r --arg k "$coin_id" '.[$k].last_updated_at // 0' <<<"$raw" 2>/dev/null || echo 0)"
  [[ -n "$price" && "$price" != "null" ]] || return 1
  previous="$(awk -v p="$price" -v pc="$pct" 'BEGIN{d=1+(pc/100); if(d!=0) printf "%.10f", p/d; else print p}')"
  quote_from_previous "$symbol" "$name" "crypto" "USD" "Crypto" "CRYPTOCURRENCY" "$price" "$previous" "$market_time" "CoinGecko"
}

fetch_one_quote() {
  local item="$1" symbol name type asset_class coin_id result=""
  symbol="$(jq -r '.symbol' <<<"$item")"
  name="$(jq -r '.name // .symbol' <<<"$item")"
  type="$(jq -r '.type // "stock"' <<<"$item")"
  asset_class="$(jq -r '.assetClass // "stocks"' <<<"$item")"
  coin_id="$(jq -r '.coinId // ""' <<<"$item")"
  if [[ "$type" == "crypto" ]]; then
    result="$(fetch_coingecko_quote "$symbol" "$name" "$coin_id" 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo_quote "$symbol" "$name" "$type" query1.finance.yahoo.com 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo_quote "$symbol" "$name" "$type" query2.finance.yahoo.com 2>/dev/null || true)"
  else
    result="$(fetch_nasdaq_quote "$symbol" "$name" "$type" "$asset_class" 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo_quote "$symbol" "$name" "$type" query1.finance.yahoo.com 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo_quote "$symbol" "$name" "$type" query2.finance.yahoo.com 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_stooq_quote "$symbol" "$name" "$type" 2>/dev/null || true)"
  fi
  if [[ -n "$result" ]]; then
    printf '%s\n' "$result"
  else
    jq -nc --arg symbol "$symbol" --arg name "$name" --arg type "$type" \
      '{symbol:$symbol,name:$name,type:$type,error:"Quote providers unavailable",provider:""}'
  fi
}

quotes() {
  migrate_config; require_cmd jq; require_cmd curl
  local force="${1:-}" ttl item tmp now
  ttl="$(jq -r '.refreshSeconds // 60' "$CONFIG_FILE")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=60
  (( ttl < 15 )) && ttl=15
  if [[ "$force" != "--force" && -f "$QUOTE_CACHE" ]] && \
     [[ "$(jq -r '.cacheVersion // 0' "$QUOTE_CACHE" 2>/dev/null || echo 0)" == "$CACHE_VERSION" ]] && \
     cache_is_fresh "$QUOTE_CACHE" "$ttl"; then
    cat "$QUOTE_CACHE"; return 0
  fi
  tmp="$(mktemp "$CACHE_DIR/.quotes.XXXXXX")"
  printf '[]' > "$tmp"
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    q="$(fetch_one_quote "$item")"
    jq --argjson q "$q" '. + [$q]' "$tmp" > "$tmp.next"
    mv "$tmp.next" "$tmp"
  done < <(jq -c '.watchlist[]' "$CONFIG_FILE")
  now="$(date +%s)"
  jq -n --argjson cacheVersion "$CACHE_VERSION" --argjson updatedAt "$now" --slurpfile q "$tmp" \
    '{cacheVersion:$cacheVersion,updatedAt:$updatedAt,quotes:$q[0]}' > "$QUOTE_CACHE"
  rm -f "$tmp"
  cat "$QUOTE_CACHE"
}

range_days() {
  case "${1^^}" in
    1D) echo 1 ;;
    5D) echo 8 ;;
    1M) echo 35 ;;
    3M) echo 100 ;;
    1Y) echo 370 ;;
    *) echo 35 ;;
  esac
}

history_ttl() {
  case "${1^^}" in
    1D) echo 90 ;;
    5D) echo 300 ;;
    1M|3M) echo 900 ;;
    1Y) echo 3600 ;;
    *) echo 900 ;;
  esac
}

history_cache_file() {
  local symbol range safe
  symbol="$(normalize_symbol "$1")"; range="${2^^}"
  safe="${symbol//[^A-Z0-9._-]/_}"
  printf '%s/%s-%s.json' "$HISTORY_DIR" "$safe" "$range"
}

history_envelope() {
  local symbol="$1" range="$2" provider="$3" points="$4"
  jq -nc --arg symbol "$symbol" --arg range "$range" --arg provider "$provider" --argjson points "$points" '
    ($points | map(.v) | map(select(. != null))) as $vals
    | ($vals[0] // 0) as $first
    | ($vals[-1] // 0) as $last
    | {
        symbol:$symbol,
        range:$range,
        provider:$provider,
        points:$points,
        start:$first,
        end:$last,
        high:(if ($vals|length)>0 then ($vals|max) else 0 end),
        low:(if ($vals|length)>0 then ($vals|min) else 0 end),
        change:($last-$first),
        changePercent:(if $first != 0 then (($last-$first)/$first*100) else 0 end)
      }
  '
}

fetch_nasdaq_history() {
  local symbol="$1" range="$2" asset_class="$3" raw points from to days
  [[ "$symbol" != *.* && "$symbol" != *-* ]] || return 1
  mapfile -t hdr < <(nasdaq_headers)
  if [[ "${range^^}" == "1D" ]]; then
    raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 12 "${hdr[@]}" \
      "https://api.nasdaq.com/api/quote/${symbol}/chart?assetclass=${asset_class:-stocks}&charttype=rs" 2>/dev/null)" || return 1
    points="$(jq -c '[.data.chart[]? | select(.x != null and .y != null) | {t:((.x/1000)|floor),v:(.y|tonumber)}]' <<<"$raw" 2>/dev/null || true)"
  else
    days="$(range_days "$range")"
    to="$(date +%Y-%m-%d)"
    from="$(date -d "$days days ago" +%Y-%m-%d)"
    raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 12 "${hdr[@]}" \
      "https://api.nasdaq.com/api/quote/${symbol}/historical?assetclass=${asset_class:-stocks}&fromdate=${from}&todate=${to}&limit=500" 2>/dev/null)" || return 1
    points="$(jq -c '[.data.tradesTable.rows[]? | select(.date != null and .close != null) | {t:(.date | strptime("%m/%d/%Y") | mktime),v:(.close | tostring | gsub("[$,]";"") | tonumber)}] | reverse' <<<"$raw" 2>/dev/null || true)"
  fi
  [[ -n "$points" && "$points" != "null" && "$(jq 'length' <<<"$points" 2>/dev/null || echo 0)" -ge 2 ]] || return 1
  history_envelope "$symbol" "$range" "Nasdaq" "$points"
}

fetch_yahoo_history() {
  local symbol="$1" range="$2" encoded yrange interval raw result points
  encoded="$(jq -rn --arg v "$symbol" '$v|@uri')"
  case "${range^^}" in
    1D) yrange=1d; interval=5m ;;
    5D) yrange=5d; interval=30m ;;
    1M) yrange=1mo; interval=1d ;;
    3M) yrange=3mo; interval=1d ;;
    1Y) yrange=1y; interval=1d ;;
    *) yrange=1mo; interval=1d ;;
  esac
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 12 \
    -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/151 Safari/537.36' \
    "https://query1.finance.yahoo.com/v8/finance/chart/${encoded}?range=${yrange}&interval=${interval}" 2>/dev/null)" || return 1
  result="$(jq -c '.chart.result[0] // empty' <<<"$raw" 2>/dev/null || true)"
  [[ -n "$result" ]] || return 1
  points="$(jq -c '[range(0; (.timestamp|length)) as $i | {t:.timestamp[$i],v:.indicators.quote[0].close[$i]} | select(.v != null)]' <<<"$result" 2>/dev/null || true)"
  [[ "$(jq 'length' <<<"$points" 2>/dev/null || echo 0)" -ge 2 ]] || return 1
  history_envelope "$symbol" "$range" "Yahoo Finance" "$points"
}

fetch_coingecko_history() {
  local symbol="$1" range="$2" coin_id="$3" days raw points
  [[ -n "$coin_id" ]] || coin_id="$(coin_id_for_symbol "$symbol")"
  case "${range^^}" in
    1D) days=1 ;;
    5D) days=5 ;;
    1M) days=30 ;;
    3M) days=90 ;;
    1Y) days=365 ;;
    *) days=30 ;;
  esac
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 12 \
    -H 'accept: application/json' -A 'omarchy-finance/0.2.0' \
    "https://api.coingecko.com/api/v3/coins/${coin_id}/market_chart?vs_currency=usd&days=${days}" 2>/dev/null)" || return 1
  points="$(jq -c '[.prices[]? | select(.[0] != null and .[1] != null) | {t:((.[0]/1000)|floor),v:(.[1]|tonumber)}]' <<<"$raw" 2>/dev/null || true)"
  [[ "$(jq 'length' <<<"$points" 2>/dev/null || echo 0)" -ge 2 ]] || return 1
  history_envelope "$symbol" "$range" "CoinGecko" "$points"
}

history() {
  migrate_config; require_cmd jq; require_cmd curl
  local symbol type range force item asset_class coin_id cache ttl result=""
  symbol="$(normalize_symbol "${1:-}")"
  type="${2:-stock}"
  range="${3:-1M}"; range="${range^^}"
  force="${4:-}"
  [[ -n "$symbol" ]] || fail "Symbol required"
  item="$(jq -c --arg s "$symbol" '.watchlist[]? | select((.symbol|ascii_upcase)==$s)' "$CONFIG_FILE" | head -n1)"
  asset_class="$(jq -r '.assetClass // "stocks"' <<<"${item:-{}}" 2>/dev/null || echo stocks)"
  coin_id="$(jq -r '.coinId // ""' <<<"${item:-{}}" 2>/dev/null || true)"
  cache="$(history_cache_file "$symbol" "$range")"
  ttl="$(history_ttl "$range")"
  if [[ "$force" != "--force" && -f "$cache" ]] && cache_is_fresh "$cache" "$ttl"; then cat "$cache"; return 0; fi
  if [[ "$type" == "crypto" ]]; then
    result="$(fetch_coingecko_history "$symbol" "$range" "$coin_id" 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo_history "$symbol" "$range" 2>/dev/null || true)"
  else
    result="$(fetch_nasdaq_history "$symbol" "$range" "$asset_class" 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo_history "$symbol" "$range" 2>/dev/null || true)"
  fi
  if [[ -z "$result" ]]; then
    result="$(jq -nc --arg symbol "$symbol" --arg range "$range" '{symbol:$symbol,range:$range,provider:"",points:[],error:"Chart data unavailable"}')"
  fi
  printf '%s\n' "$result" > "$cache"
  cat "$cache"
}

dashboard() {
  migrate_config
  local force="${1:-}" q item symbol type h out tmp
  q="$(quotes "$force")"
  tmp="$(mktemp "$CACHE_DIR/.dashboard.XXXXXX")"
  printf '[]' > "$tmp"
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    symbol="$(jq -r '.symbol' <<<"$item")"
    type="$(jq -r '.type // "stock"' <<<"$item")"
    h="$(history "$symbol" "$type" 5D "${force:-}" 2>/dev/null || jq -nc --arg symbol "$symbol" '{symbol:$symbol,points:[]}')"
    jq --argjson item "$item" --argjson h "$h" '. + [($item + {sparkline:($h.points // []),sparkProvider:($h.provider // "")})]' "$tmp" > "$tmp.next"
    mv "$tmp.next" "$tmp"
  done < <(jq -c '.watchlist[]' "$CONFIG_FILE")
  jq -n --argjson config "$(cat "$CONFIG_FILE")" --argjson quotes "$q" --slurpfile assets "$tmp" \
    '{config:$config,quotes:($quotes.quotes // []),updatedAt:($quotes.updatedAt // 0),assets:$assets[0]}'
  rm -f "$tmp"
}

diagnose() {
  migrate_config
  require_cmd jq; require_cmd curl
  printf 'Finance v0.2.0\n'
  printf 'Config: %s\n' "$CONFIG_FILE"
  printf 'Watchlist: %s assets\n' "$(jq '.watchlist|length' "$CONFIG_FILE")"
  local aapl btc
  aapl='{"symbol":"AAPL","name":"Apple","type":"stock","assetClass":"stocks","coinId":""}'
  btc='{"symbol":"BTC-USD","name":"Bitcoin","type":"crypto","assetClass":"crypto","coinId":"bitcoin"}'
  fetch_nasdaq_quote AAPL Apple stock stocks >/dev/null 2>&1 && echo 'Nasdaq quote: OK' || echo 'Nasdaq quote: FAILED'
  fetch_nasdaq_history AAPL 1M stocks >/dev/null 2>&1 && echo 'Nasdaq history: OK' || echo 'Nasdaq history: FAILED'
  fetch_coingecko_quote BTC-USD Bitcoin bitcoin >/dev/null 2>&1 && echo 'CoinGecko quote: OK' || echo 'CoinGecko quote: FAILED'
  fetch_coingecko_history BTC-USD 1M bitcoin >/dev/null 2>&1 && echo 'CoinGecko history: OK' || echo 'CoinGecko history: FAILED'
  fetch_yahoo_quote AAPL Apple stock query1.finance.yahoo.com >/dev/null 2>&1 && echo 'Yahoo fallback: OK' || echo 'Yahoo fallback: FAILED'
  fetch_stooq_quote AAPL Apple stock >/dev/null 2>&1 && echo 'Stooq fallback: OK' || echo 'Stooq fallback: FAILED'
}

migrate_config

case "${1:-config}" in
  config) config ;;
  catalog) catalog ;;
  add) shift; add_asset "$@" ;;
  remove) shift; remove_asset "$@" ;;
  quotes) shift; quotes "${1:-}" ;;
  dashboard) shift; dashboard "${1:-}" ;;
  history) shift; history "$@" ;;
  diagnose) diagnose ;;
  *) fail "Usage: $0 {config|catalog|add|remove|quotes|dashboard|history|diagnose}" ;;
esac
