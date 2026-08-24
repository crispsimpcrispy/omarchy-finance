# Omarchy Finance Watchlist

A Quattro top-bar plugin for monitoring stocks, shares and cryptocurrency.

Default watchlist:

- Apple (`AAPL`)
- Tesla (`TSLA`)
- Bitcoin (`BTC-USD`)

## Features

- Native Omarchy `bar-widget` with anchored popup panel.
- Rotating top-bar summary such as `AAPL +0.8%`.
- Current price, daily absolute change and percentage change.
- Stocks and crypto in the same watchlist.
- Add/remove symbols from the panel.
- Supports non-US Yahoo-style symbols such as London `.L` tickers.
- Cached quotes to avoid unnecessary requests.
- Middle-click the bar widget to force a refresh.

## Data source

v0.1.0 uses Yahoo Finance's undocumented `v8/finance/chart` JSON endpoint. It does not require an API key, which keeps local installation simple, but it is not an official supported API and can change or become unavailable. Data may also be delayed.

This plugin is intended for personal monitoring only, not order execution or investment decisions.

## Files

```text
manifest.json
BarWidget.qml
Panel.qml
backend.sh
self-test.sh
README.md
LICENSE
```

User settings are stored outside the plugin checkout:

```text
~/.config/omarchy/finance/watchlist.json
```

Cached prices are stored under:

```text
~/.cache/omarchy-finance/quotes.json
```

This means Git/plugin updates do not overwrite your watchlist.

## Validate

On your Omarchy machine:

```bash
./self-test.sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
```

## Suggested repository

```text
https://github.com/crispsimpcrispy/omarchy-finance
```

Install after publishing:

```bash
omarchy plugin add https://github.com/crispsimpcrispy/omarchy-finance.git --enable
omarchy restart shell
```

Future updates:

```bash
omarchy plugin update io.github.crispsimpcrispy.finance --yes
omarchy restart shell
```

## Symbols

Examples:

```text
AAPL       Apple
TSLA       Tesla
MSFT       Microsoft
RR.L       Rolls-Royce Holdings (London)
BTC-USD    Bitcoin / US dollar
ETH-USD    Ethereum / US dollar
```
