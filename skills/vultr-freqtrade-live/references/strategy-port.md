# Porting a backtested rule set to freqtrade

A port is a reimplementation. The numbers will differ until every one of the items below is
matched; after that the ledgers match trade for trade (verified: 53 of 54 trades identical,
the 54th being the forced close on a different end date).

## The template

`assets/user_data/strategies/EmaCrossStopLock.py` implements the shape most simple rule sets
take: indicator crossover entry, crossover exit, fixed stop, and a lock after a losing stop.
Replace the indicator lines and keep everything else.

## Where ports silently diverge

| Item | freqtrade setting | Why it matters |
|---|---|---|
| Fill model | `order_types` entry/exit `market`, signals on closed candles | Fills at the **next candle's open**; a backtester that fills on the signal candle's close shifts every trade by one bar |
| Stop | `stoploss = -0.05` (fraction of entry) | Freqtrade evaluates the stop against the candle's low and fills at the stop price; intrabar order is assumed. `--timeframe-detail 1h` tightens this |
| Fees | `--fee 0.001` on the CLI, `fee_open/fee_close` in results | 0.1% each way makes a −5% stop show as ≈ −5.19% |
| Take-profit | `minimal_roi = {}` | Left unset, freqtrade's default is `{"0": 10}` — a 1000% target that never fires; but a strategy generated from freqtrade's template carries an active ROI table that adds exits the original never had. `{}` states the intent either way |
| Trailing | `trailing_stop = False` | Default is off, say so explicitly |
| Exit signal | `use_exit_signal = True`, `exit_profit_only = False` | Otherwise crossover exits are ignored |
| Post-stop lock | `protections` → `StoplossGuard` with `lookback_period_candles: 1`, `trade_limit: 1`, `stop_duration_candles: N`, `only_per_pair: True`, `required_profit: 0.0` | Locks the pair's entries for N candles after one losing stop. **Backtests need `--enable-protections`** or it is silently off |
| Warm-up | `startup_candle_count` ≥ longest indicator (with margin) and a download `--timerange` that starts earlier than the backtest | Otherwise the first weeks of signals are missing or shifted |
| Position size | `stake_amount: "unlimited"`, `tradable_balance_ratio: 0.995`, `max_open_trades: 1` | All-in compounding on the account's stake-currency balance (the ratio is of the total balance); `1.0` leaves nothing for the entry fee and the order is rejected |
| Candle validity | `& (dataframe["volume"] > 0)` in entry/exit | Matches backtesters that skip zero-volume candles |
| Direction | `can_short = False` | Spot is long-only |
| Re-entry after lock | crossover, not level | `crossed_above` fires only on the crossing candle; a rule that re-enters whenever fast > slow is a different strategy |

## Mechanics

- Indicators through `talib.abstract` (`ta.EMA(dataframe, timeperiod=12)`); crossings through
  `technical.qtpylib.crossed_above/crossed_below`.
- `process_only_new_candles = True` on a daily strategy.
- `INTERFACE_VERSION = 3`, entry/exit columns `enter_long` / `exit_long` with tags.
- Syntax-check locally before uploading (`python -m py_compile <file>`); the real check is
  `docker compose run --rm freqtrade list-strategies` on the VPS showing the strategy as `OK`.

## TradingView as a cross-check (optional)

If the person also holds the rule set as a Pine strategy, two settings inflate its results and
were the cause of a 100-trade, margin-call-laden run: `default_qty_value = 100` percent of equity
with commission (no cash left for the fee → forced liquidation rows) and `calc_on_order_fills =
true` (re-entries inside the same bar). Use 99.5%, and expect the trade count, not the total
return, to be the comparable number.
