# Ledger parity — the gate before live

Two engines that agree on total return can disagree on every trade; two engines that agree on
every trade agree on what a port has to get right — the signals and the fill semantics.
(Amounts, the fee currency, lot rounding and the equity curve between trades can still differ.)
Compare ledgers, not totals, and do it before an exchange key exists anywhere.

## What to compare, per trade

| Column | freqtrade result JSON (`trades[]`) | Tolerance |
|---|---|---|
| open date | `open_date` | exact day (daily timeframe) |
| close date | `close_date` | exact day |
| open rate | `open_rate` | exact (same candle open) |
| close rate | `close_rate` | exact for signal exits; stop exits at the stop price |
| exit reason | `exit_reason` (`exit_signal` / `stop_loss` / `force_exit`) | exact |
| profit ratio | `profit_ratio` | ≤ 1e-6 (fee rounding) |

Order both ledgers by open date and walk them side by side. `scripts/extract-trades.py`
writes the freqtrade side as CSV from the result zip; the original backtester's export is
whatever it offers (a trades table, a CSV, a SQL view) — sort it the same way.

## Expected differences that are not bugs

- **The final forced exit.** Each engine closes the last open trade on its own end date; if the
  ranges end a day apart, the last row differs in close date, rate and profit. Everything before
  it must still match.
- **Stop timestamps under `--timeframe-detail`.** Hourly detail records the hour the stop hit; a
  daily engine records the day at 00:00. Same day, same price, different clock — compare the
  daily run for exactness and the detail run for sensitivity.
- **1 in 50 at the edges.** A different EMA seed (SMA-seeded vs first-value-seeded) or a
  different first candle shifts an early crossover by a bar. If the first divergent trade is in
  the first few weeks and everything after it matches, that is warm-up, not logic.

## Differences that are bugs — check in this order

1. **Trade count off by many** → protections not enabled (`--enable-protections` missing) or
   `minimal_roi` not emptied (extra `roi` exits) or trailing stop on.
2. **Every trade one bar late/early** → fill model (next-open vs same-close) or the signal
   evaluated on an unclosed candle.
3. **Stops fill at different prices** → stop measured from a different base (entry fill vs
   signal close) or the backtester fills stops at the candle close.
4. **Profit ratios off by ~0.2%** → fee applied on one side only, or fee 0 in one engine.
5. **Trades missing in a run of losses** → the lock length or the "one losing stop" trigger
   differs (`trade_limit`, `lookback_period_candles`).

## Acceptance

State it as a sentence with the numbers: "N of M trades identical on date, rate, reason and
ratio; the remaining K are <the expected difference above>". Only then move to
[live-cutover.md](live-cutover.md). If the person waves the last mismatch through ("the
final one doesn't matter"), write that down too.
