#!/usr/bin/env bash
set -euo pipefail

# Daily backtest. Edit the pair, the strategy name and the two ranges; keep the flags.
PAIR="${PAIR:-BTC/USDT}"
STRATEGY="${STRATEGY:-EmaCrossStopLock}"
DATA_RANGE="${DATA_RANGE:-20170817-20260903}"   # start early enough for startup_candle_count
TEST_RANGE="${TEST_RANGE:-20180401-20260901}"

docker compose pull

docker compose run --rm freqtrade download-data \
  --config user_data/config.json \
  --pairs "$PAIR" \
  --timeframes 1d \
  --timerange "$DATA_RANGE"

# --enable-protections: without it the post-stop lock never runs and the run still succeeds.
# --cache none: a cached run hides a config change.
docker compose run --rm freqtrade backtesting \
  --config user_data/config.json \
  --strategy "$STRATEGY" \
  --pairs "$PAIR" \
  --timeframe 1d \
  --timerange "$TEST_RANGE" \
  --dry-run-wallet 1000 \
  --fee 0.001 \
  --enable-protections \
  --cache none \
  --export trades \
  --breakdown year
