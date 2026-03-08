from fastapi import APIRouter, Depends, Query, HTTPException
from typing import Optional
from database import prediction_col, energy_col, devices_col
from app.models.prediction_model import Prediction
from datetime import datetime, timedelta
from utils.jwt_handler import get_current_user
import pandas as pd
import sys
from pathlib import Path

# Add backend directory to path
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from app.services.lstm_service import LSTMPredictor
import threading
from app.services.ownership import get_owner_user_id

router = APIRouter(
    prefix="/prediction",
    tags=["Prediction"],
    dependencies=[Depends(get_current_user)],
)

# Initialize LSTM service (lazy loading with thread safety)
_lstm_service = None
_lstm_lock = threading.Lock()

def get_lstm_service():
    """Lazy load LSTM service (thread-safe)"""
    global _lstm_service
    with _lstm_lock:
        if _lstm_service is None:
            svc = LSTMPredictor(model_dir='models')
            svc.load_model()
            _lstm_service = svc
        return _lstm_service if _lstm_service.is_trained else None

@router.post("/")
def save_prediction(prediction: Prediction, current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)
    doc = prediction.dict()
    doc["created_at"] = datetime.utcnow()
    doc["owner_user_id"] = owner_user_id
    prediction_col.insert_one(doc)
    return {"message": "Prediction saved"}

@router.get("/daily")
def get_daily_predictions():
    """Get daily predictions from database"""
    return list(prediction_col.find({"prediction_type": "daily"}, {"_id": 0}).sort("created_at", -1).limit(100))

@router.get("/predict")
def predict_energy(
    location: Optional[str] = Query(None, description="Filter by location"),
    hours_ahead: int = Query(24, ge=1, le=168, description="Hours ahead to predict"),
):
    """
    Predict future energy consumption using LSTM time series model
    """
    try:
        lstm_service = get_lstm_service()

        if lstm_service is None:
            raise HTTPException(status_code=503, detail="LSTM model not trained. Please train models first.")

        # Get recent data for prediction
        cutoff_time = datetime.utcnow() - timedelta(hours=48)
        query = {"received_at": {"$gte": cutoff_time}}
        if location:
            query["location"] = location

        # Get energy readings
        cursor = energy_col.find(query).sort("received_at", -1).limit(200)
        data = []
        for doc in cursor:
            received_at = doc.get("received_at", {})
            if isinstance(received_at, dict) and "$date" in received_at:
                timestamp = datetime.fromisoformat(received_at["$date"].replace("Z", "+00:00"))
            elif isinstance(received_at, datetime):
                timestamp = received_at
            else:
                continue

            data.append({
                "module": doc.get("module"),
                "location": doc.get("location"),
                "current_a": doc.get("current_a", 0),
                "power_w": doc.get("power_w") or (doc.get("current_a", 0) * 230),
                "received_at": timestamp
            })

        if len(data) < 10:
            raise HTTPException(status_code=400, detail="Not enough data for prediction. Need at least 10 readings.")

        df = pd.DataFrame(data)
        df = df.sort_values('received_at')

        # Use LSTM for time series prediction
        predictions_df = lstm_service.predict(df.tail(50), steps_ahead=min(hours_ahead, 24))
        predictions = predictions_df['predicted_power_w'].tolist()

        avg_power = float(predictions_df['predicted_power_w'].mean())

        # Save prediction to database
        prediction_doc = {
            "device_id": location or "all",
            "predicted_energy_kwh": float(avg_power / 1000.0),
            "confidence_score": 0.85,
            "prediction_type": "real-time",
            "created_at": datetime.utcnow(),
            "hours_ahead": len(predictions)
        }
        prediction_col.insert_one(prediction_doc)

        return {
            "model_type": "lstm",
            "location": location,
            "hours_ahead": len(predictions),
            "predictions": [
                {
                    "step": i + 1,
                    "predicted_power_w": float(pred),
                    "timestamp": (datetime.utcnow() + timedelta(hours=i+1)).isoformat()
                }
                for i, pred in enumerate(predictions)
            ],
            "average_power": avg_power,
            "predicted_energy_kwh": float(avg_power / 1000.0)
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Prediction failed: {str(e)}")


@router.get("/weekly-forecast")
def weekly_forecast(
    location: Optional[str] = Query(None, description="Filter by location"),
):
    """
    Predict energy consumption for the next 7 days.

    Returns a daily breakdown (Mon-Sun) of predicted kWh, plus a weekly total.
    Uses the LSTM model to forecast hourly power, then aggregates into daily
    and weekly summaries.
    """
    try:
        lstm_service = get_lstm_service()
        if lstm_service is None:
            raise HTTPException(
                status_code=503,
                detail="LSTM model not trained yet. Please train models first.",
            )

        # Get recent 48h of energy readings for context
        cutoff = datetime.utcnow() - timedelta(hours=48)
        query = {"received_at": {"$gte": cutoff}}
        if location:
            query["location"] = location

        cursor = energy_col.find(query).sort("received_at", -1).limit(300)
        data = []
        for doc in cursor:
            ts = doc.get("received_at")
            if isinstance(ts, dict) and "$date" in ts:
                ts = datetime.fromisoformat(ts["$date"].replace("Z", "+00:00"))
            elif not isinstance(ts, datetime):
                continue
            data.append({
                "module": doc.get("module"),
                "location": doc.get("location"),
                "current_a": doc.get("current_a", 0),
                "power_w": doc.get("power_w") or (doc.get("current_a", 0) * 230),
                "received_at": ts,
            })

        if len(data) < 10:
            raise HTTPException(
                status_code=400,
                detail="Not enough recent data for a weekly forecast. Need at least 10 readings.",
            )

        df = pd.DataFrame(data).sort_values("received_at")

        # LSTM predicts up to 24 steps at a time.
        # We call it multiple times to cover 7 days (168 hours).
        all_predictions = []
        input_slice = df.tail(50)

        # Predict in 24-hour chunks
        for day_idx in range(7):
            steps = min(24, 168 - len(all_predictions))
            if steps <= 0:
                break
            try:
                pred_df = lstm_service.predict(input_slice, steps_ahead=steps)
                day_preds = pred_df["predicted_power_w"].tolist()
                all_predictions.extend(day_preds)

                # Build a pseudo-input for the next chunk using predictions
                new_rows = []
                base_time = datetime.utcnow() + timedelta(hours=len(all_predictions) - len(day_preds))
                for i, pw in enumerate(day_preds):
                    new_rows.append({
                        "module": input_slice.iloc[-1].get("module", ""),
                        "location": location or input_slice.iloc[-1].get("location", ""),
                        "current_a": pw / 230.0,
                        "power_w": pw,
                        "received_at": base_time + timedelta(hours=i + 1),
                    })
                if new_rows:
                    input_slice = pd.DataFrame(new_rows)
            except Exception:
                # If prediction fails on later days, use the average of existing predictions
                avg_so_far = sum(all_predictions) / len(all_predictions) if all_predictions else 0
                remaining = 168 - len(all_predictions)
                all_predictions.extend([avg_so_far] * remaining)
                break

        # Aggregate into daily breakdown
        now = datetime.utcnow()
        day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        daily_breakdown = []
        weekly_total_kwh = 0.0

        for day_offset in range(7):
            start_hour = day_offset * 24
            end_hour = min(start_hour + 24, len(all_predictions))
            day_powers = all_predictions[start_hour:end_hour]

            if not day_powers:
                continue

            # Energy (kWh) = average power (W) / 1000 * hours
            avg_power_w = sum(day_powers) / len(day_powers)
            day_kwh = avg_power_w * len(day_powers) / 1000.0
            weekly_total_kwh += day_kwh

            target_date = now + timedelta(days=day_offset + 1)
            day_name = day_names[target_date.weekday()]

            daily_breakdown.append({
                "day": day_name,
                "date": target_date.strftime("%Y-%m-%d"),
                "predicted_kwh": round(day_kwh, 3),
                "avg_power_w": round(avg_power_w, 1),
                "peak_power_w": round(max(day_powers), 1),
                "hours_predicted": len(day_powers),
            })

        # Save forecast
        prediction_col.insert_one({
            "device_id": location or "all",
            "predicted_energy_kwh": round(weekly_total_kwh, 3),
            "confidence_score": 0.80,
            "prediction_type": "weekly_forecast",
            "created_at": datetime.utcnow(),
            "hours_ahead": len(all_predictions),
            "daily_breakdown": daily_breakdown,
        })

        return {
            "model_type": "lstm",
            "location": location,
            "forecast_days": len(daily_breakdown),
            "weekly_total_kwh": round(weekly_total_kwh, 3),
            "daily_breakdown": daily_breakdown,
            "generated_at": datetime.utcnow().isoformat(),
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Weekly forecast failed: {str(e)}")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_energy_doc(doc):
    """Parse a single energy reading document into a dict with proper timestamp."""
    ts = doc.get("received_at") or doc.get("receivedAt") or doc.get("timestamp")
    if isinstance(ts, dict) and "$date" in ts:
        try:
            ts = datetime.fromisoformat(ts["$date"].replace("Z", "+00:00"))
        except (ValueError, TypeError):
            return None
    elif isinstance(ts, str):
        try:
            ts = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except (ValueError, TypeError):
            return None
    elif not isinstance(ts, datetime):
        return None
    return {
        "module": doc.get("module"),
        "location": doc.get("location"),
        "current_a": doc.get("current_a", 0),
        "power_w": doc.get("power_w") or (doc.get("current_a", 0) * 230),
        "received_at": ts,
    }


def _run_7day_lstm_forecast(df, lstm_service, location=None):
    """
    Run LSTM predictions for 7 days (168 hours) in 24-hour chunks.

    Returns:
        all_predictions: list of 168 predicted power_w values (hourly)
    """
    all_predictions = []
    input_slice = df.tail(50)

    for day_idx in range(7):
        steps = min(24, 168 - len(all_predictions))
        if steps <= 0:
            break
        try:
            pred_df = lstm_service.predict(input_slice, steps_ahead=steps)
            day_preds = pred_df["predicted_power_w"].tolist()
            all_predictions.extend(day_preds)

            new_rows = []
            base_time = datetime.utcnow() + timedelta(hours=len(all_predictions) - len(day_preds))
            for i, pw in enumerate(day_preds):
                new_rows.append({
                    "module": input_slice.iloc[-1].get("module", ""),
                    "location": location or input_slice.iloc[-1].get("location", ""),
                    "current_a": pw / 230.0,
                    "power_w": pw,
                    "received_at": base_time + timedelta(hours=i + 1),
                })
            if new_rows:
                input_slice = pd.DataFrame(new_rows)
        except Exception:
            avg_so_far = sum(all_predictions) / len(all_predictions) if all_predictions else 0
            remaining = 168 - len(all_predictions)
            all_predictions.extend([avg_so_far] * remaining)
            break

    return all_predictions


def _aggregate_daily(readings_data, start_date, num_days, is_historical=False):
    """
    Aggregate a list of reading dicts into daily summaries.

    For historical data, computes actual_kwh from real readings.
    For forecast data, computes predicted_kwh from hourly power predictions.
    """
    day_names_map = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    daily = []

    if is_historical and readings_data:
        df = pd.DataFrame(readings_data)
        df["received_at"] = pd.to_datetime(df["received_at"])
        df = df.sort_values("received_at")
        df["date"] = df["received_at"].dt.date

        for day_offset in range(num_days):
            target_date = start_date + timedelta(days=day_offset)
            day_df = df[df["date"] == target_date.date()]

            if day_df.empty:
                daily.append({
                    "day": day_names_map[target_date.weekday()],
                    "date": target_date.strftime("%Y-%m-%d"),
                    "actual_kwh": 0.0,
                    "avg_power_w": 0.0,
                    "peak_power_w": 0.0,
                    "readings_count": 0,
                })
                continue

            powers = day_df["power_w"].values
            avg_pw = float(powers.mean())
            # Estimate kWh: avg power * hours covered
            time_span = (day_df["received_at"].max() - day_df["received_at"].min()).total_seconds() / 3600.0
            if time_span < 0.1:
                time_span = len(powers) * (30 / 3600.0)  # assume ~30s intervals
            actual_kwh = avg_pw * time_span / 1000.0

            daily.append({
                "day": day_names_map[target_date.weekday()],
                "date": target_date.strftime("%Y-%m-%d"),
                "actual_kwh": round(actual_kwh, 3),
                "avg_power_w": round(avg_pw, 1),
                "peak_power_w": round(float(powers.max()), 1),
                "readings_count": len(day_df),
            })
    return daily


# ---------------------------------------------------------------------------
# Per-device forecast endpoint
# ---------------------------------------------------------------------------

@router.get("/device-forecast/{device_id}")
def device_forecast(
    device_id: str,
    rate_per_kwh: float = Query(42.5, ge=0, description="Electricity rate in LKR per kWh"),
):
    """
    Get a 7-day energy forecast for a specific device.

    Returns forecast, historical comparison, risk level, and cost projections.
    Uses the device's module_id to query its energy readings, then runs the
    LSTM model for a 7-day (168-hour) prediction.
    """
    try:
        lstm_service = get_lstm_service()
        if lstm_service is None:
            raise HTTPException(
                status_code=503,
                detail="LSTM model not trained yet. Please train models first.",
            )

        # 1. Look up device
        device = devices_col.find_one({"device_id": device_id}, {"_id": 0})
        if not device:
            raise HTTPException(status_code=404, detail=f"Device not found: {device_id}")

        module_id = device.get("module_id")
        if not module_id:
            raise HTTPException(
                status_code=400,
                detail=f"Device {device_id} has no module_id assigned. Cannot generate forecast.",
            )

        device_name = device.get("device_name", device_id)
        location = device.get("location", "")

        now = datetime.utcnow()

        # 2. Get last 7 days of actual energy data for this device
        cutoff_7d = now - timedelta(hours=168)
        cursor_recent = energy_col.find(
            {"module": module_id, "received_at": {"$gte": cutoff_7d}},
        ).sort("received_at", -1).limit(5000)

        recent_data = []
        for doc in cursor_recent:
            parsed = _parse_energy_doc(doc)
            if parsed:
                recent_data.append(parsed)

        # Fallback: if time-range query returned too few results, try without time filter
        if len(recent_data) < 10:
            cursor_all = energy_col.find(
                {"module": module_id},
            ).sort("received_at", -1).limit(5000)
            recent_data = []
            for doc in cursor_all:
                parsed = _parse_energy_doc(doc)
                if parsed:
                    recent_data.append(parsed)

        if len(recent_data) < 10:
            raise HTTPException(
                status_code=400,
                detail=f"Not enough data for device {device_id} (module: {module_id}). "
                       f"Found {len(recent_data)} readings, need at least 10.",
            )

        # Historical daily aggregation (last 7 days)
        hist_start = now - timedelta(days=7)
        daily_historical = _aggregate_daily(recent_data, hist_start, 7, is_historical=True)
        historical_total_kwh = sum(d["actual_kwh"] for d in daily_historical)

        # 3. Get previous week (days 8-14 ago) for comparison
        cutoff_14d = now - timedelta(hours=336)
        cursor_prev = energy_col.find(
            {"module": module_id, "received_at": {"$gte": cutoff_14d, "$lt": cutoff_7d}},
        ).sort("received_at", -1).limit(5000)

        prev_data = []
        for doc in cursor_prev:
            parsed = _parse_energy_doc(doc)
            if parsed:
                prev_data.append(parsed)

        prev_start = now - timedelta(days=14)
        daily_prev = _aggregate_daily(prev_data, prev_start, 7, is_historical=True)
        last_week_total_kwh = sum(d["actual_kwh"] for d in daily_prev)

        # 4. Run LSTM 7-day forecast
        df = pd.DataFrame(recent_data).sort_values("received_at")
        all_predictions = _run_7day_lstm_forecast(df, lstm_service, location)

        # 5. Aggregate forecast into daily breakdown
        day_names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        daily_forecast = []
        weekly_total_kwh = 0.0

        for day_offset in range(7):
            start_hour = day_offset * 24
            end_hour = min(start_hour + 24, len(all_predictions))
            day_powers = all_predictions[start_hour:end_hour]

            if not day_powers:
                continue

            avg_power_w = sum(day_powers) / len(day_powers)
            day_kwh = avg_power_w * len(day_powers) / 1000.0
            weekly_total_kwh += day_kwh

            target_date = now + timedelta(days=day_offset + 1)
            day_name = day_names[target_date.weekday()]

            # Find peak hour
            peak_idx = day_powers.index(max(day_powers))
            peak_hour = peak_idx  # hour 0-23

            daily_forecast.append({
                "day": day_name,
                "date": target_date.strftime("%Y-%m-%d"),
                "predicted_kwh": round(day_kwh, 3),
                "avg_power_w": round(avg_power_w, 1),
                "peak_power_w": round(max(day_powers), 1),
                "peak_hour": peak_hour,
                "confidence_low_kwh": round(day_kwh * 0.85, 3),
                "confidence_high_kwh": round(day_kwh * 1.15, 3),
                "hours_predicted": len(day_powers),
            })

        # 6. Comparison metrics
        historical_avg_daily = historical_total_kwh / 7.0 if historical_total_kwh > 0 else 0
        if last_week_total_kwh > 0:
            percent_change = ((weekly_total_kwh - last_week_total_kwh) / last_week_total_kwh) * 100
        else:
            percent_change = 0.0

        if percent_change > 5:
            trend = "rising"
        elif percent_change < -5:
            trend = "falling"
        else:
            trend = "stable"

        # Risk level based on forecast vs historical average
        if historical_avg_daily > 0:
            forecast_avg_daily = weekly_total_kwh / 7.0
            ratio = forecast_avg_daily / historical_avg_daily
            if ratio > 1.3:
                risk_level = "red"
                risk_reason = "Predicted consumption significantly above historical average. Review device usage patterns."
            elif ratio > 1.1:
                risk_level = "orange"
                risk_reason = "Predicted increase due to rising usage pattern."
            else:
                risk_level = "green"
                risk_reason = "Normal consumption expected based on historical trends."
        else:
            risk_level = "green"
            risk_reason = "Insufficient historical data for comparison."

        # 7. Cost projections
        weekly_cost_lkr = weekly_total_kwh * rate_per_kwh
        monthly_projection_lkr = weekly_cost_lkr * (30.0 / 7.0)
        last_week_cost_lkr = last_week_total_kwh * rate_per_kwh
        savings_10pct = weekly_cost_lkr * 0.1

        # Save forecast
        prediction_col.insert_one({
            "device_id": device_id,
            "predicted_energy_kwh": round(weekly_total_kwh, 3),
            "confidence_score": 0.80,
            "prediction_type": "device_weekly_forecast",
            "created_at": now,
            "hours_ahead": len(all_predictions),
            "daily_forecast": daily_forecast,
        })

        return {
            "device_id": device_id,
            "device_name": device_name,
            "module_id": module_id,
            "location": location,
            "model_type": "lstm",
            "forecast_days": len(daily_forecast),
            "weekly_total_kwh": round(weekly_total_kwh, 3),
            "daily_forecast": daily_forecast,
            "historical_days": len(daily_historical),
            "historical_total_kwh": round(historical_total_kwh, 3),
            "daily_historical": daily_historical,
            "comparison": {
                "percent_change": round(percent_change, 2),
                "trend": trend,
                "risk_level": risk_level,
                "risk_reason": risk_reason,
                "historical_avg_daily_kwh": round(historical_avg_daily, 3),
            },
            "cost": {
                "rate_per_kwh_lkr": rate_per_kwh,
                "weekly_cost_lkr": round(weekly_cost_lkr, 2),
                "monthly_projection_lkr": round(monthly_projection_lkr, 2),
                "last_week_cost_lkr": round(last_week_cost_lkr, 2),
                "weekly_savings_if_reduced_10pct_lkr": round(savings_10pct, 2),
            },
            "generated_at": now.isoformat(),
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Device forecast failed: {str(e)}")


# ---------------------------------------------------------------------------
# Device comparison endpoint
# ---------------------------------------------------------------------------

@router.get("/device-comparison")
def device_comparison(
    rate_per_kwh: float = Query(42.5, ge=0, description="Electricity rate in LKR per kWh"),
):
    """
    Get predicted weekly consumption for all devices, ranked by usage.

    Returns a ranked list of devices sorted by predicted weekly kWh (descending).
    Useful for facility managers to quickly identify heavy consumers.
    """
    try:
        lstm_service = get_lstm_service()
        if lstm_service is None:
            raise HTTPException(
                status_code=503,
                detail="LSTM model not trained yet. Please train models first.",
            )

        now = datetime.utcnow()
        cutoff_7d = now - timedelta(hours=168)
        cutoff_14d = now - timedelta(hours=336)

        # Get all devices with module_id
        all_devices = list(devices_col.find(
            {"module_id": {"$ne": None, "$exists": True}},
            {"_id": 0},
        ))

        device_results = []

        for device in all_devices:
            device_id = device.get("device_id", "")
            module_id = device.get("module_id")
            device_name = device.get("device_name", device_id)
            location = device.get("location", "")

            if not module_id:
                continue

            try:
                # Get recent data for this device
                cursor = energy_col.find(
                    {"module": module_id, "received_at": {"$gte": cutoff_7d}},
                ).sort("received_at", -1).limit(2000)

                recent_data = []
                for doc in cursor:
                    parsed = _parse_energy_doc(doc)
                    if parsed:
                        recent_data.append(parsed)

                # Fallback: try without time filter
                if len(recent_data) < 10:
                    cursor_all = energy_col.find(
                        {"module": module_id},
                    ).sort("received_at", -1).limit(2000)
                    recent_data = []
                    for doc in cursor_all:
                        parsed = _parse_energy_doc(doc)
                        if parsed:
                            recent_data.append(parsed)

                if len(recent_data) < 10:
                    continue

                # Get previous week for comparison
                cursor_prev = energy_col.find(
                    {"module": module_id, "received_at": {"$gte": cutoff_14d, "$lt": cutoff_7d}},
                ).sort("received_at", -1).limit(2000)

                prev_data = []
                for doc in cursor_prev:
                    parsed = _parse_energy_doc(doc)
                    if parsed:
                        prev_data.append(parsed)

                prev_start = now - timedelta(days=14)
                daily_prev = _aggregate_daily(prev_data, prev_start, 7, is_historical=True)
                last_week_total = sum(d["actual_kwh"] for d in daily_prev)

                # Run forecast
                df = pd.DataFrame(recent_data).sort_values("received_at")
                all_predictions = _run_7day_lstm_forecast(df, lstm_service, location)

                # Compute totals
                weekly_kwh = 0.0
                for day_offset in range(7):
                    start_h = day_offset * 24
                    end_h = min(start_h + 24, len(all_predictions))
                    day_powers = all_predictions[start_h:end_h]
                    if day_powers:
                        avg_pw = sum(day_powers) / len(day_powers)
                        weekly_kwh += avg_pw * len(day_powers) / 1000.0

                # Comparison
                if last_week_total > 0:
                    pct = ((weekly_kwh - last_week_total) / last_week_total) * 100
                else:
                    pct = 0.0

                trend = "rising" if pct > 5 else ("falling" if pct < -5 else "stable")

                hist_start = now - timedelta(days=7)
                daily_hist = _aggregate_daily(recent_data, hist_start, 7, is_historical=True)
                hist_total = sum(d["actual_kwh"] for d in daily_hist)
                hist_avg_daily = hist_total / 7.0 if hist_total > 0 else 0
                forecast_avg_daily = weekly_kwh / 7.0

                if hist_avg_daily > 0:
                    ratio = forecast_avg_daily / hist_avg_daily
                    risk = "red" if ratio > 1.3 else ("orange" if ratio > 1.1 else "green")
                else:
                    risk = "green"

                device_results.append({
                    "device_id": device_id,
                    "device_name": device_name,
                    "location": location,
                    "predicted_weekly_kwh": round(weekly_kwh, 3),
                    "weekly_cost_lkr": round(weekly_kwh * rate_per_kwh, 2),
                    "risk_level": risk,
                    "trend": trend,
                    "percent_change": round(pct, 2),
                })
            except Exception:
                # Skip devices that fail prediction
                continue

        # Sort by predicted consumption descending
        device_results.sort(key=lambda d: d["predicted_weekly_kwh"], reverse=True)

        total_kwh = sum(d["predicted_weekly_kwh"] for d in device_results)
        total_cost = sum(d["weekly_cost_lkr"] for d in device_results)

        return {
            "devices": device_results,
            "total_predicted_kwh": round(total_kwh, 3),
            "total_weekly_cost_lkr": round(total_cost, 2),
            "rate_per_kwh_lkr": rate_per_kwh,
            "device_count": len(device_results),
            "generated_at": now.isoformat(),
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Device comparison failed: {str(e)}")
def get_daily_predictions(current_user=Depends(get_current_user)):
    owner_user_id = get_owner_user_id(current_user)
    return list(prediction_col.find({"prediction_type": "daily", "owner_user_id": owner_user_id}, {"_id": 0}))
