"""
Generate a 2000-row CSV dataset for current energy analysis recommendations.
Each row: current reading features + recommendation_type, severity, savings, waste.
Used to train the current energy recommendation model for the analytics page.

Usage: python scripts/generate_current_energy_recommendations_dataset.py
Output: data/current_energy_recommendations_dataset.csv
"""

import csv
import random
from pathlib import Path

# Output path
BACKEND_DIR = Path(__file__).resolve().parent.parent
OUTPUT_PATH = BACKEND_DIR / "data" / "current_energy_recommendations_dataset.csv"

# Recommendation types and rules (for accurate labeling)
# high_load: power_w >= 800 or current_a >= 4
# moderate_load: 400 <= power_w < 800 or 2 <= current_a < 4
# rising_consumption: trend=rising, percent_change > 10, power_w > 100
# weak_signal: signal_quality = weak
# efficient_usage: power_w < 400, power_w > 0, not rising, not weak

TREND_DIRECTIONS = ("stable", "rising", "falling")
SIGNAL_QUALITIES = ("strong", "fair", "weak")
RECOMMENDATION_TYPES = (
    "high_load",
    "moderate_load",
    "rising_consumption",
    "weak_signal",
    "efficient_usage",
)


def _power_w(current_a: float) -> float:
    return round(current_a * 230.0, 2)


def _current_ma(current_a: float) -> float:
    return round(current_a * 1000.0, 2)


def _assign_recommendation(
    current_a: float,
    power_w: float,
    trend_direction: str,
    trend_percent_change: float,
    signal_quality: str,
) -> tuple[str, str, float, float]:
    """Return (recommendation_type, severity, estimated_savings_kwh_per_day, energy_wasted_kwh_per_day)."""
    # Priority: weak_signal (device issue), high_load, rising, moderate, efficient
    if signal_quality == "weak":
        return ("weak_signal", "low", 0.0, 0.0)

    if power_w >= 800 or current_a >= 4.0:
        wasted = (power_w * 24) / 1000
        savings = wasted * 0.35
        return ("high_load", "high", round(savings, 4), round(wasted, 4))

    if trend_direction == "rising" and trend_percent_change > 10 and power_w > 100:
        extra_kwh = (power_w * (trend_percent_change / 100) * 24) / 1000
        return ("rising_consumption", "medium", round(extra_kwh * 0.5, 4), round(extra_kwh, 4))

    if power_w >= 400 or current_a >= 2.0:
        wasted = (power_w * 24) / 1000
        return ("moderate_load", "medium", round(wasted * 0.2, 4), round(wasted * 0.15, 4))

    if power_w > 0:
        return ("efficient_usage", "low", 0.0, 0.0)

    return ("efficient_usage", "low", 0.0, 0.0)


def generate_row(target_type: str) -> dict:
    """Generate one row targeting a specific recommendation_type with realistic features."""
    while True:
        if target_type == "high_load":
            current_a = round(random.uniform(3.5, 12.0), 4)
            trend_direction = random.choice(TREND_DIRECTIONS)
            trend_pct = round(random.uniform(-15, 25), 2)
            signal_quality = random.choices(SIGNAL_QUALITIES, weights=[70, 20, 10])[0]
        elif target_type == "moderate_load":
            current_a = round(random.uniform(1.8, 4.5), 4)
            if current_a >= 4.0:
                current_a = round(random.uniform(1.8, 3.8), 4)
            trend_direction = random.choice(TREND_DIRECTIONS)
            trend_pct = round(random.uniform(-20, 20), 2)
            signal_quality = random.choices(SIGNAL_QUALITIES, weights=[75, 20, 5])[0]
        elif target_type == "rising_consumption":
            current_a = round(random.uniform(0.5, 6.0), 4)
            trend_direction = "rising"
            trend_pct = round(random.uniform(10.5, 45.0), 2)
            signal_quality = random.choices(SIGNAL_QUALITIES, weights=[80, 15, 5])[0]
        elif target_type == "weak_signal":
            current_a = round(random.uniform(0.0, 5.0), 4)
            trend_direction = random.choice(TREND_DIRECTIONS)
            trend_pct = round(random.uniform(-10, 10), 2)
            signal_quality = "weak"
        else:  # efficient_usage
            current_a = round(random.uniform(0.05, 1.7), 4)
            trend_direction = random.choices(TREND_DIRECTIONS, weights=[80, 10, 10])[0]
            trend_pct = round(random.uniform(-8, 8), 2) if trend_direction != "rising" else round(random.uniform(-5, 5), 2)
            signal_quality = random.choices(SIGNAL_QUALITIES, weights=[85, 12, 3])[0]

        power_w = _power_w(current_a)
        current_ma = _current_ma(current_a)
        rec_type, severity, savings, wasted = _assign_recommendation(
            current_a, power_w, trend_direction, trend_pct, signal_quality
        )
        if rec_type == target_type:
            return {
                "current_a": current_a,
                "current_ma": current_ma,
                "power_w": power_w,
                "trend_direction": trend_direction,
                "trend_percent_change": trend_pct,
                "signal_quality": signal_quality,
                "recommendation_type": rec_type,
                "severity": severity,
                "estimated_savings_kwh_per_day": savings,
                "energy_wasted_kwh_per_day": wasted,
            }
    return None


def main():
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    # 2000 rows: 400 per recommendation type
    n_per_type = 400
    rows = []
    for rec_type in RECOMMENDATION_TYPES:
        for _ in range(n_per_type):
            rows.append(generate_row(rec_type))

    fieldnames = [
        "current_a",
        "current_ma",
        "power_w",
        "trend_direction",
        "trend_percent_change",
        "signal_quality",
        "recommendation_type",
        "severity",
        "estimated_savings_kwh_per_day",
        "energy_wasted_kwh_per_day",
    ]
    with open(OUTPUT_PATH, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(rows)

    print(f"Generated {len(rows)} rows at {OUTPUT_PATH}")
    for rt in RECOMMENDATION_TYPES:
        count = sum(1 for r in rows if r["recommendation_type"] == rt)
        print(f"  {rt}: {count}")


if __name__ == "__main__":
    main()
