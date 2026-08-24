#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="io.github.crispsimpcrispy.finance"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_DIR="$CONFIG_HOME/omarchy/finance"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy-finance"
CONFIG_FILE="$STATE_DIR/watchlist.json"
CACHE_FILE="$CACHE_DIR/quotes.json"

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

config() {
  seed_config
  cat "$CONFIG_FILE"
}

normalize_symbol() {
  local s="${1:-}"
  s="${s//[[:space:]]/}"
  printf '%s' "${s^^}"
}

add_asset() {
  seed_config
  require_cmd jq
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
  local ttl now modified
  ttl="$(jq -r '.refreshSeconds // 60' "$CONFIG_FILE")"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=60
  (( ttl < 15 )) && ttl=15
  now="$(date +%s)"
  modified="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)"
  (( now - modified < ttl ))
}

fetch_one() {
  local item="$1" symbol encoded raw result meta price previous change pct currency exchange instrument name type market_time
  symbol="$(jq -r '.symbol' <<<"$item")"
  name="$(jq -r '.name // .symbol' <<<"$item")"
  type="$(jq -r '.type // "stock"' <<<"$item")"
  encoded="$(jq -rn --arg v "$symbol" '$v|@uri')"

  if ! raw="$(curl -fsSL --retry 1 --connect-timeout 4 --max-time 10 \
      -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131 Safari/537.36' \
      "https://query1.finance.yahoo.com/v8/finance/chart/${encoded}?range=1d&interval=5m" 2>/dev/null)"; then
    jq -nc --arg symbol "$symbol" --arg name "$name" --arg type "$type" \
      '{symbol:$symbol,name:$name,type:$type,error:"Network request failed"}'
    return 0
  fi

  result="$(jq -c '.chart.result[0] // empty' <<<"$raw" 2>/dev/null || true)"
  if [[ -z "$result" ]]; then
    jq -nc --arg symbol "$symbol" --arg name "$name" --arg type "$type" \
      '{symbol:$symbol,name:$name,type:$type,error:"Quote unavailable"}'
    return 0
  fi

  meta="$(jq -c '.meta // {}' <<<"$result")"
  price="$(jq -r '.regularMarketPrice // empty' <<<"$meta")"
  if [[ -z "$price" || "$price" == "null" ]]; then
    price="$(jq -r '[.indicators.quote[0].close[]? | select(. != null)] | last // empty' <<<"$result")"
  fi
  previous="$(jq -r '.previousClose // .chartPreviousClose // empty' <<<"$meta")"
  currency="$(jq -r '.currency // ""' <<<"$meta")"
  exchange="$(jq -r '.exchangeName // ""' <<<"$meta")"
  instrument="$(jq -r '.instrumentType // ""' <<<"$meta")"
  market_time="$(jq -r '.regularMarketTime // 0' <<<"$meta")"

  if [[ -z "$price" || "$price" == "null" ]]; then
    jq -nc --arg symbol "$symbol" --arg name "$name" --arg type "$type" \
      '{symbol:$symbol,name:$name,type:$type,error:"Price unavailable"}'
    return 0
  fi

  if [[ -n "$previous" && "$previous" != "null" ]] && awk -v p="$previous" 'BEGIN{exit !(p!=0)}'; then
    change="$(awk -v p="$price" -v prev="$previous" 'BEGIN{printf "%.10f", p-prev}')"
    pct="$(awk -v p="$price" -v prev="$previous" 'BEGIN{printf "%.10f", ((p-prev)/prev)*100}')"
  else
    change="0"
    pct="0"
  fi

  local formatted
  formatted="$(awk -v p="$price" -v c="$currency" 'BEGIN {
    decimals=(p<1 ? 4 : 2);
    if (c=="USD") symbol="$";
    else if (c=="GBP") symbol="£";
    else if (c=="EUR") symbol="€";
    else symbol="";
    printf "%s%.*f", symbol, decimals, p;
  }')"

  jq -nc \
    --arg symbol "$symbol" --arg name "$name" --arg type "$type" \
    --arg currency "$currency" --arg exchange "$exchange" --arg instrumentType "$instrument" \
    --arg priceFormatted "$formatted" \
    --argjson price "$price" --argjson previousClose "${previous:-0}" \
    --argjson change "$change" --argjson changePercent "$pct" --argjson marketTime "${market_time:-0}" \
    '{symbol:$symbol,name:$name,type:$type,currency:$currency,exchange:$exchange,instrumentType:$instrumentType,price:$price,priceFormatted:$priceFormatted,previousClose:$previousClose,change:$change,changePercent:$changePercent,marketTime:$marketTime}'
}

fetch_quotes() {
  seed_config
  require_cmd jq
  require_cmd curl
  local force="${1:-}" item tmp_quotes tmp_line now

  if [[ "$force" != "--force" ]] && cache_is_fresh; then
    cat "$CACHE_FILE"
    return 0
  fi

  tmp_quotes="$(mktemp "$CACHE_DIR/.quotes-lines.XXXXXX")"
  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    fetch_one "$item" >> "$tmp_quotes"
  done < <(jq -c '.watchlist[]?' "$CONFIG_FILE")

  now="$(date +%s)"
  jq -s --argjson updatedAt "$now" '{updatedAt:$updatedAt,quotes:.}' "$tmp_quotes" > "$CACHE_FILE.tmp"
  mv "$CACHE_FILE.tmp" "$CACHE_FILE"
  rm -f "$tmp_quotes"
  cat "$CACHE_FILE"
}

case "${1:-config}" in
  config) config ;;
  quotes) shift; fetch_quotes "${1:-}" ;;
  add) shift; add_asset "$@" ;;
  remove) shift; remove_asset "$@" ;;
  *) fail "Usage: $0 {config|quotes [--force]|add SYMBOL [NAME] [stock|crypto]|remove SYMBOL}" ;;
esac
