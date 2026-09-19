#!/usr/bin/env bash
set -euo pipefail

# Same backtest with hourly candles refining intrabar stop timing. Run it AFTER the daily
# one, never alongside it, on a 1 GB instance. If trade count, stop count and return do not
# move, the result does not hang on intrabar assumptions.
PAIR="${PAIR:-BTC/USDT}"
STRATEGY="${STRATEGY:-EmaCrossStopLock}"
DATA_RANGE="${DATA_RANGE:-20170817-20260903}"
TEST_RANGE="${TEST_RANGE:-20180401-20260901}"

docker compose pull

docker compose run --rm freqtrade download-data \
  --config user_data/config.json \
  --pairs "$PAIR" \
  --timeframes 1d 1h \
  --timerange "$DATA_RANGE"

docker compose run --rm freqtrade backtesting \
  --config user_data/config.json \
  --strategy "$STRATEGY" \
  --pairs "$PAIR" \
  --timeframe 1d \
  --timeframe-detail 1h \
  --timerange "$TEST_RANGE" \
  --dry-run-wallet 1000 \
  --fee 0.001 \
  --enable-protections \
  --cache none \
  --export trades \
  --breakdown year
