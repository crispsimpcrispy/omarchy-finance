# Omarchy Finance

A Quattro-native top-bar finance watchlist for stocks, shares and cryptocurrency.

## v0.2.0

Finance v0.2.0 is a major UI and data-layer rebuild:

- polished market-card watchlist
- mini sparklines for every asset
- click any asset for a full detail view
- 1D / 5D / 1M / 3M / 1Y chart ranges
- range high, range low, previous close and provider
- popular-asset picker for stocks and crypto
- custom ticker entry for anything not in the picker
- rotating top-bar price/change summary
- existing v0.1 watchlists are migrated automatically
- stock quotes/charts prefer Nasdaq public web endpoints
- crypto quotes/charts prefer CoinGecko
- Yahoo Finance and Stooq remain quote/history fallbacks where applicable

The default watchlist contains Apple (`AAPL`), Tesla (`TSLA`) and Bitcoin (`BTC-USD`).

## Files

```text
manifest.json
BarWidget.qml
Panel.qml
Sparkline.qml
backend.sh
self-test.sh
```

User data lives outside the plugin folder:

```text
~/.config/omarchy/finance/watchlist.json
~/.cache/omarchy-finance/
```

Plugin updates therefore do not overwrite the watchlist.

## Validate

```bash
./self-test.sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Sparkline.qml
```

The included self-test mocks remote providers, so it can validate parsing and fallback behaviour without contacting live markets.

## Install from GitHub

```bash
omarchy plugin add https://github.com/crispsimpcrispy/omarchy-finance.git --enable
omarchy restart shell
```

## Update

```bash
omarchy plugin update io.github.crispsimpcrispy.finance --yes
omarchy restart shell
```

## Controls

- Left-click the top-bar widget: open Finance.
- Middle-click the top-bar widget: force quote refresh.
- Click a watchlist card: open its chart/detail screen.
- Use `+ Add` to browse popular assets or add a custom ticker.

## Data notes

This plugin is intended as a convenient personal watchlist, not a trading terminal. Public web/data endpoints can be delayed, rate-limited or changed by their providers. The backend caches quote and history responses and fails gracefully when a source is unavailable.

Nasdaq support is strongest for US-listed shares and ETFs. International symbols can fall back to Yahoo Finance/Stooq when those feeds support the ticker. Crypto uses CoinGecko IDs; common symbols such as BTC, ETH, SOL, XRP, ADA, DOGE and LINK are mapped automatically.

## License

MIT
