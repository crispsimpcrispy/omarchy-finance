#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="io.github.crispsimpcrispy.finance"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="$CONFIG_HOME/omarchy/finance"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-finance"
CONFIG_FILE="$STATE_DIR/watchlist.json"
CACHE_FILE="$CACHE_DIR/quotes.json"
CACHE_VERSION=2

mkdir -p "$STATE_DIR" "$CACHE_DIR"

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }

seed_config() {
  [[ -f "$CONFIG_FILE" ]] && return 0
  cat > "$CONFIG_FILE" <<'JSON'
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

config() { seed_config; cat "$CONFIG_FILE"; }

normalize_symbol() {
  local s="${1:-}"
  s="${s//[[:space:]]/}"
  printf '%s' "${s^^}"
}

add_asset() {
  seed_config; require_cmd jq
  local symbol name type
  symbol="$(normalize_symbol "${1:-}")"
  name="${2:-}"
  type="${3:-stock}"
  [[ -n "$symbol" ]] || fail "Symbol cannot be empty"
  [[ "$type" == "stock" || "$type" == "crypto" ]] || type="stock"
  [[ -n "$name" ]] || name="$symbol"
  if jq -e --arg s "$symbol" '.watchlist[]? | select((.symbol|ascii_upcase)==$s)' "$CONFIG_FILE" >/dev/null; then
    fail "$symbol is already on the watchlist"
  fi
  atomic_jq '.watchlist += [{symbol:$symbol,name:$name,type:$type}]' \
    --arg symbol "$symbol" --arg name "$name" --arg type "$type"
  rm -f "$CACHE_FILE"
  printf 'Added %s.\n' "$symbol"
}

remove_asset() {
  seed_config
  local symbol
  symbol="$(normalize_symbol "${1:-}")"
  [[ -n "$symbol" ]] || fail "Symbol cannot be empty"
  atomic_jq '.watchlist |= map(select((.symbol|ascii_upcase)!=$symbol))' --arg symbol "$symbol"
  rm -f "$CACHE_FILE"
  printf 'Removed %s.\n' "$symbol"
}

cache_is_fresh() {
  [[ -f "$CACHE_FILE" ]] || return 1
  [[ "$(jq -r '.cacheVersion // 0' "$CACHE_FILE" 2>/dev/null || echo 0)" == "$CACHE_VERSION" ]] || return 1
  local ttl now modified
  ttl="$(jq -r '.refreshSeconds // 60' "$CONFIG_FILE")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=60
  (( ttl < 15 )) && ttl=15
  now="$(date +%s)"
  modified="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)"
  (( now - modified < ttl ))
}

format_price() {
  local price="$1" currency="$2"
  awk -v p="$price" -v c="$currency" 'BEGIN {
    decimals=(p<1 ? 4 : 2);
    if (c=="USD") s="$"; else if (c=="GBP") s="£"; else if (c=="EUR") s="€"; else s="";
    printf "%s%.*f", s, decimals, p;
  }'
}

quote_json() {
  local symbol="$1" name="$2" type="$3" currency="$4" exchange="$5" instrument="$6" price="$7" previous="$8" market_time="$9" provider="${10}"
  local change pct formatted
  if [[ -n "$previous" && "$previous" != "null" ]] && awk -v p="$previous" 'BEGIN{exit !(p!=0)}'; then
    change="$(awk -v p="$price" -v prev="$previous" 'BEGIN{printf "%.10f", p-prev}')"
    pct="$(awk -v p="$price" -v prev="$previous" 'BEGIN{printf "%.10f", ((p-prev)/prev)*100}')"
  else
    change="0"; pct="0"; previous="0"
  fi
  formatted="$(format_price "$price" "$currency")"
  jq -nc \
    --arg symbol "$symbol" --arg name "$name" --arg type "$type" \
    --arg currency "$currency" --arg exchange "$exchange" --arg instrumentType "$instrument" \
    --arg priceFormatted "$formatted" --arg provider "$provider" \
    --argjson price "$price" --argjson previousClose "$previous" \
    --argjson change "$change" --argjson changePercent "$pct" --argjson marketTime "${market_time:-0}" \
    '{symbol:$symbol,name:$name,type:$type,currency:$currency,exchange:$exchange,instrumentType:$instrumentType,provider:$provider,price:$price,priceFormatted:$priceFormatted,previousClose:$previousClose,change:$change,changePercent:$changePercent,marketTime:$marketTime}'
}

fetch_yahoo() {
  local symbol="$1" name="$2" type="$3" host="${4:-query1.finance.yahoo.com}" encoded raw result meta price previous currency exchange instrument market_time
  encoded="$(jq -rn --arg v "$symbol" '$v|@uri')"
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
    -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131 Safari/537.36' \
    "https://${host}/v8/finance/chart/${encoded}?range=1d&interval=5m" 2>/dev/null)" || return 1
  result="$(jq -c '.chart.result[0] // empty' <<<"$raw" 2>/dev/null || true)"
  [[ -n "$result" ]] || return 1
  meta="$(jq -c '.meta // {}' <<<"$result")"
  price="$(jq -r '.regularMarketPrice // empty' <<<"$meta")"
  [[ -n "$price" && "$price" != "null" ]] || price="$(jq -r '[.indicators.quote[0].close[]? | select(. != null)] | last // empty' <<<"$result")"
  [[ -n "$price" && "$price" != "null" ]] || return 1
  previous="$(jq -r '.previousClose // .chartPreviousClose // empty' <<<"$meta")"
  currency="$(jq -r '.currency // ""' <<<"$meta")"
  exchange="$(jq -r '.exchangeName // "Yahoo"' <<<"$meta")"
  instrument="$(jq -r '.instrumentType // ""' <<<"$meta")"
  market_time="$(jq -r '.regularMarketTime // 0' <<<"$meta")"
  quote_json "$symbol" "$name" "$type" "$currency" "$exchange" "$instrument" "$price" "${previous:-0}" "$market_time" "Yahoo Finance"
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

fetch_stooq() {
  local symbol="$1" name="$2" type="$3" ss raw line sdate stime open high low close volume previous
  ss="$(stooq_symbol "$symbol")"
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
    -A 'Mozilla/5.0 (X11; Linux x86_64)' \
    "https://stooq.com/q/l/?s=${ss}&f=sd2t2ohlcvp&h&e=csv" 2>/dev/null)" || return 1
  [[ "$raw" != *"Exceeded"* && "$raw" != *"apikey"* ]] || return 1
  line="$(printf '%s\n' "$raw" | tail -n1 | tr -d '\r')"
  [[ -n "$line" && "$line" != Symbol,* ]] || return 1
  IFS=',' read -r _ sdate stime open high low close volume previous <<<"$line"
  [[ -n "$close" && "$close" != "N/D" ]] || return 1
  [[ -n "$previous" && "$previous" != "N/D" ]] || previous="$open"
  quote_json "$symbol" "$name" "$type" "USD" "Stooq" "EQUITY" "$close" "${previous:-0}" 0 "Stooq"
}

crypto_base_symbol() {
  local s="${1^^}"
  s="${s%%-*}"
  printf '%s' "${s,,}"
}

fetch_coingecko() {
  local symbol="$1" name="$2" type="$3" base raw price pct market_time previous
  base="$(crypto_base_symbol "$symbol")"
  [[ -n "$base" ]] || return 1
  raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
    -H 'accept: application/json' \
    -A 'omarchy-finance/0.1.1' \
    "https://api.coingecko.com/api/v3/simple/price?symbols=${base}&vs_currencies=usd&include_24hr_change=true&include_last_updated_at=true" 2>/dev/null)" || return 1
  price="$(jq -r --arg k "$base" '.[$k].usd // empty' <<<"$raw" 2>/dev/null || true)"
  pct="$(jq -r --arg k "$base" '.[$k].usd_24h_change // empty' <<<"$raw" 2>/dev/null || true)"
  market_time="$(jq -r --arg k "$base" '.[$k].last_updated_at // 0' <<<"$raw" 2>/dev/null || true)"
  [[ -n "$price" && "$price" != "null" ]] || return 1
  if [[ -n "$pct" && "$pct" != "null" ]]; then
    previous="$(awk -v p="$price" -v pc="$pct" 'BEGIN{d=1+(pc/100); if(d!=0) printf "%.10f", p/d; else print 0}')"
  else
    previous="$price"
  fi
  quote_json "$symbol" "$name" "$type" "USD" "CoinGecko" "CRYPTOCURRENCY" "$price" "$previous" "$market_time" "CoinGecko"
}

fetch_one() {
  local item="$1" symbol name type result=""
  symbol="$(jq -r '.symbol' <<<"$item")"
  name="$(jq -r '.name // .symbol' <<<"$item")"
  type="$(jq -r '.type // "stock"' <<<"$item")"

  if [[ "$type" == "crypto" ]]; then
    result="$(fetch_coingecko "$symbol" "$name" "$type" 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo "$symbol" "$name" "$type" query1.finance.yahoo.com 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo "$symbol" "$name" "$type" query2.finance.yahoo.com 2>/dev/null || true)"
  else
    result="$(fetch_yahoo "$symbol" "$name" "$type" query1.finance.yahoo.com 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_yahoo "$symbol" "$name" "$type" query2.finance.yahoo.com 2>/dev/null || true)"
    [[ -n "$result" ]] || result="$(fetch_stooq "$symbol" "$name" "$type" 2>/dev/null || true)"
  fi

  if [[ -n "$result" ]]; then
    printf '%s\n' "$result"
  else
    jq -nc --arg symbol "$symbol" --arg name "$name" --arg type "$type" \
      '{symbol:$symbol,name:$name,type:$type,error:"All quote providers failed",provider:""}'
  fi
}

fetch_quotes() {
  seed_config; require_cmd jq; require_cmd curl
  local force="${1:-}" item tmp_quotes now
  if [[ "$force" != "--force" ]] && cache_is_fresh; then cat "$CACHE_FILE"; return 0; fi
  tmp_quotes="$(mktemp "$CACHE_DIR/.quotes-lines.XXXXXX")"
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    fetch_one "$item" >> "$tmp_quotes"
  done < <(jq -c '.watchlist[]?' "$CONFIG_FILE")
  now="$(date +%s)"
  jq -s --argjson updatedAt "$now" --argjson cacheVersion "$CACHE_VERSION" \
    '{cacheVersion:$cacheVersion,updatedAt:$updatedAt,quotes:.}' "$tmp_quotes" > "$CACHE_FILE.tmp"
  mv "$CACHE_FILE.tmp" "$CACHE_FILE"
  rm -f "$tmp_quotes"
  cat "$CACHE_FILE"
}

diagnose() {
  seed_config
  require_cmd jq
  require_cmd curl
  printf 'curl: %s\n' "$(command -v curl)"
  printf 'jq: %s\n' "$(command -v jq)"
  printf 'Yahoo query1: '
  if curl -fsSL --connect-timeout 4 --max-time 8 -A 'Mozilla/5.0' 'https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=5m' 2>/dev/null | jq -e '.chart.result[0].meta.regularMarketPrice' >/dev/null 2>&1; then echo OK; else echo FAILED; fi
  printf 'Yahoo query2: '
  if curl -fsSL --connect-timeout 4 --max-time 8 -A 'Mozilla/5.0' 'https://query2.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=5m' 2>/dev/null | jq -e '.chart.result[0].meta.regularMarketPrice' >/dev/null 2>&1; then echo OK; else echo FAILED; fi
  printf 'CoinGecko: '
  if curl -fsSL --connect-timeout 4 --max-time 8 -H 'accept: application/json' 'https://api.coingecko.com/api/v3/simple/price?symbols=btc&vs_currencies=usd' 2>/dev/null | jq -e '.btc.usd' >/dev/null 2>&1; then echo OK; else echo FAILED; fi
  printf 'Stooq: '
  if curl -fsSL --connect-timeout 4 --max-time 8 -A 'Mozilla/5.0' 'https://stooq.com/q/l/?s=aapl.us&f=sd2t2ohlcvp&h&e=csv' 2>/dev/null | tail -n1 | grep -vq 'N/D'; then echo OK; else echo FAILED; fi
}

case "${1:-config}" in
  config) config ;;
  quotes) shift; fetch_quotes "${1:-}" ;;
  add) shift; add_asset "$@" ;;
  remove) shift; remove_asset "$@" ;;
  diagnose) diagnose ;;
  *) fail "Usage: $0 {config|quotes [--force]|add SYMBOL [NAME] [stock|crypto]|remove SYMBOL|diagnose}" ;;
esac
