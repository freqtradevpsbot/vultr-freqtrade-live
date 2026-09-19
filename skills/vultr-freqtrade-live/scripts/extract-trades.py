#!/usr/bin/env python3
"""Turn a freqtrade backtest result zip into the CSV the ledger-parity step compares.

Usage:
    python3 extract-trades.py backtest-result-<stamp>.zip [out.csv]

Standard library only, so it runs on the VPS and on the person's machine alike. Prints a
one-line summary (trades, locks, final balance) and writes one row per trade, sorted by
open date, with the six columns the parity table names.
"""

import csv
import json
import sys
import zipfile
from pathlib import Path

COLUMNS = [
    "open_date", "close_date", "open_rate", "close_rate", "exit_reason",
    "profit_ratio", "profit_abs", "enter_tag", "trade_duration",
]


def load_result(zip_path: Path) -> dict:
    with zipfile.ZipFile(zip_path) as z:
        names = [n for n in z.namelist() if n.endswith(".json") and not n.endswith("_config.json")]
        if not names:
            raise SystemExit(f"no result json inside {zip_path}")
        with z.open(names[0]) as f:
            return json.load(f)


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    zip_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else zip_path.with_suffix(".trades.csv")

    data = load_result(zip_path)
    strategies = data.get("strategy", {})
    if len(strategies) != 1:
        raise SystemExit(f"expected one strategy in the result, found {list(strategies)}")
    name, result = next(iter(strategies.items()))

    trades = sorted(result.get("trades", []), key=lambda t: (t["open_date"], t["close_date"]))
    with out_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
        w.writeheader()
        for t in trades:
            w.writerow({k: t.get(k) for k in COLUMNS})

    locks = result.get("locks", [])
    print(
        f"{name}: {len(trades)} trades, {len(locks)} locks, "
        f"final balance {result.get('final_balance')}, "
        f"range {result.get('backtest_start')} -> {result.get('backtest_end')} -> {out_path}"
    )
    # The startup-state read (references/live-cutover.md, step 6): a trade force-closed exactly
    # at backtest_end means the strategy was still in position at the last closed candle.
    if trades:
        last = trades[-1]
        held = last.get("exit_reason") == "force_exit" and str(last.get("close_date", "")).startswith(
            str(result.get("backtest_end", ""))[:10]
        )
        print(
            f"last trade: {last.get('open_date')} -> {last.get('close_date')} "
            f"{last.get('exit_reason')} -> {'IN POSITION at range end' if held else 'flat at range end'}"
        )


if __name__ == "__main__":
    main()
