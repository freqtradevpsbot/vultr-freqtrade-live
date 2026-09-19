"""EMA crossover with a fixed stop and a post-stop lock: a freqtrade port template.

Rules (change the three numbers and the indicator lines; keep the rest):
- Enter long when EMA(fast) crosses above EMA(slow) on a closed candle with volume.
- Exit when EMA(fast) crosses below EMA(slow).
- Stop loss STOP_PCT below the entry fill.
- After a losing stop, refuse entries on this pair for LOCK_CANDLES candles.

Backtests must pass --enable-protections or the lock is silently disabled.
"""

from pandas import DataFrame
import talib.abstract as ta

from freqtrade.strategy import IStrategy
from technical import qtpylib


FAST = 12
SLOW = 16
STOP_PCT = -0.05
LOCK_CANDLES = 10


class EmaCrossStopLock(IStrategy):
    INTERFACE_VERSION = 3

    timeframe = "1d"
    can_short = False
    process_only_new_candles = True
    # Longest indicator plus margin; the data download must start earlier than the backtest.
    startup_candle_count = 50

    # No take-profit table: positions leave only on a crossunder, the stop, or the forced
    # close at the end of a backtest. Freqtrade's default ROI table would add exits.
    minimal_roi = {}
    stoploss = STOP_PCT
    trailing_stop = False

    use_exit_signal = True
    exit_profit_only = False
    ignore_roi_if_entry_signal = False

    # Market orders fill at the next candle's open, the model most backtesters use.
    # The live overlay (config-live.json) replaces this block to put the stop on the exchange.
    order_types = {
        "entry": "market",
        "exit": "market",
        "emergency_exit": "market",
        "force_entry": "market",
        "force_exit": "market",
        "stoploss": "market",
        "stoploss_on_exchange": False,
        "stoploss_on_exchange_interval": 60,
    }

    @property
    def protections(self):
        """Lock the pair for LOCK_CANDLES candles after one losing stop."""
        return [
            {
                "method": "StoplossGuard",
                "lookback_period_candles": 1,
                "trade_limit": 1,
                "stop_duration_candles": LOCK_CANDLES,
                "required_profit": 0.0,
                "only_per_pair": True,
                "only_per_side": False,
            }
        ]

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe["ema_fast"] = ta.EMA(dataframe, timeperiod=FAST)
        dataframe["ema_slow"] = ta.EMA(dataframe, timeperiod=SLOW)
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            qtpylib.crossed_above(dataframe["ema_fast"], dataframe["ema_slow"])
            & (dataframe["volume"] > 0),
            ["enter_long", "enter_tag"],
        ] = (1, "ema_cross_up")
        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[
            qtpylib.crossed_below(dataframe["ema_fast"], dataframe["ema_slow"])
            & (dataframe["volume"] > 0),
            ["exit_long", "exit_tag"],
        ] = (1, "ema_cross_down")
        return dataframe
