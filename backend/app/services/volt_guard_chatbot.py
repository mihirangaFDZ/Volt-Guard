"""
Volt Guard AI Chatbot - answers from real database data + FAQ dataset (static + custom).
Uses TF-IDF for FAQ; queries MongoDB for live data (devices, energy, anomalies,
predictions, occupancy, faults). Returns suggestions. Supports adding/updating custom Q&A.
"""

import json
import os
import re
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

VOLTAGE_DEFAULT = 230.0

# Sri Lankan CEB domestic tariff (30-day billing cycle; official table)
# 0–60 kWh: 0–30 @ 4.50, 31–60 @ 8.00; fixed 80/210. Above 60: 0–60 @ 12.75,
# 61–90 @ 18.50, 91–120 @ 24.00, 121–180 @ 41.00, >180 @ 61.00; fixed 400/1000/1500/2100


def _calculate_monthly_lkr(monthly_kwh: float) -> float:
    """Apply CEB domestic tariff to monthly kWh; return LKR."""
    if monthly_kwh <= 0:
        return 0.0
    energy_cost = 0.0
    fixed_lkr = 0.0

    if monthly_kwh <= 60:
        u1 = min(monthly_kwh, 30.0)
        u2 = max(monthly_kwh - 30.0, 0.0)
        energy_cost = u1 * 4.50 + u2 * 8.00
        fixed_lkr = 80.0 if monthly_kwh <= 30 else 210.0
    else:
        remaining = monthly_kwh
        energy_cost += min(remaining, 60.0) * 12.75
        remaining -= 60.0
        if remaining > 0:
            energy_cost += min(remaining, 30.0) * 18.50
            remaining -= 30.0
        if remaining > 0:
            energy_cost += min(remaining, 30.0) * 24.00
            remaining -= 30.0
        if remaining > 0:
            energy_cost += min(remaining, 60.0) * 41.00
            remaining -= 60.0
        if remaining > 0:
            energy_cost += remaining * 61.00
        if monthly_kwh <= 90:
            fixed_lkr = 400.0
        elif monthly_kwh <= 120:
            fixed_lkr = 1000.0
        elif monthly_kwh <= 180:
            fixed_lkr = 1500.0
        else:
            fixed_lkr = 2100.0

    return round(energy_cost + fixed_lkr, 2)


def _kwh_to_lkr(kwh: float, period_days: float) -> float:
    """Convert kWh over period_days to approximate LKR (prorated from monthly CEB)."""
    if kwh <= 0 or period_days <= 0:
        return 0.0
    monthly_kwh = kwh * (30.0 / period_days)
    monthly_cost = _calculate_monthly_lkr(monthly_kwh)
    return round(monthly_cost * (period_days / 30.0), 2)


def _default_dataset_path() -> str:
    base = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return os.path.join(base, "volt_guard_dataset.json")


# Default suggestions when no context
DEFAULT_SUGGESTIONS = [
    "Analyze my Volt Guard system",
    "What is my consumption today?",
    "How many devices do I have?",
    "Any recent anomalies?",
]

# Follow-up suggestions by intent (shown after user asks something related)
FOLLOW_UP_BY_INTENT: Dict[str, List[str]] = {
    "system_analysis": [
        "What is my consumption today?",
        "Top power consumers?",
        "Any recent anomalies?",
        "What are my predictions?",
    ],
    "predictions": [
        "What is my consumption today?",
        "Analyze my Volt Guard system",
        "Top power consumers?",
        "Any recent anomalies?",
    ],
    "consumption_today": [
        "Estimated monthly cost?",
        "Top power consumers?",
        "Analyze my Volt Guard system",
        "What are my predictions?",
    ],
    "energy": [
        "What is my consumption today?",
        "Top power consumers?",
        "Estimated monthly cost?",
        "Analyze my Volt Guard system",
    ],
    "devices": [
        "What is my consumption today?",
        "Top power consumers?",
        "Any recent anomalies?",
        "Analyze my Volt Guard system",
    ],
    "anomalies": [
        "Analyze my Volt Guard system",
        "What is my consumption today?",
        "Any faults?",
        "What locations are monitored?",
    ],
    "locations": [
        "What is my consumption today?",
        "How many devices do I have?",
        "Occupancy status?",
        "Analyze my Volt Guard system",
    ],
    "faults": [
        "Any recent anomalies?",
        "Analyze my Volt Guard system",
        "How many devices do I have?",
        "Device health?",
    ],
    "top_consumers": [
        "What is my consumption today?",
        "Estimated monthly cost?",
        "Analyze my Volt Guard system",
        "What are my predictions?",
    ],
    "occupancy": [
        "What is my consumption today?",
        "What locations are monitored?",
        "Analyze my Volt Guard system",
        "Any recent anomalies?",
    ],
}


class VoltGuardChatbot:
    """Chatbot: DB data answers + normal/FAQ answers + suggestions + custom dataset."""

    def __init__(self, dataset_path: Optional[str] = None, use_db: bool = True):
        self.dataset_path = dataset_path or _default_dataset_path()
        self.use_db = use_db
        self.questions: List[str] = []
        self.answers: List[str] = []
        self.vectorizer: Optional[TfidfVectorizer] = None
        self.question_vectors = None
        self._db = None
        if use_db:
            try:
                from database import (
                    devices_col,
                    energy_col,
                    anomaly_col,
                    analytics_col,
                    chatbot_custom_qa_col,
                    faults_col,
                    prediction_col,
                )
                self._devices_col = devices_col
                self._energy_col = energy_col
                self._anomaly_col = anomaly_col
                self._analytics_col = analytics_col
                self._chatbot_custom_qa_col = chatbot_custom_qa_col
                self._faults_col = faults_col
                self._prediction_col = prediction_col
                self._db = True
            except Exception:
                self._db = None
                self._faults_col = None
                self._prediction_col = None

    def _load_static_dataset(self) -> List[Tuple[str, str]]:
        """Load Q&A pairs from JSON file."""
        pairs: List[Tuple[str, str]] = []
        if not os.path.exists(self.dataset_path):
            return pairs
        with open(self.dataset_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        for c in data.get("conversations", []):
            q, a = c.get("question", "").strip(), c.get("answer", "").strip()
            if q and a:
                pairs.append((q, a))
        return pairs

    def _load_custom_dataset(self) -> List[Tuple[str, str]]:
        """Load custom Q&A from MongoDB."""
        pairs: List[Tuple[str, str]] = []
        if self._db is not True or getattr(self, "_chatbot_custom_qa_col", None) is None:
            return pairs
        try:
            col = getattr(self, "_chatbot_custom_qa_col", None)
            if col is None:
                return pairs
            for doc in col.find({}, {"_id": 0, "question": 1, "answer": 1}):
                q = (doc.get("question") or "").strip()
                a = (doc.get("answer") or "").strip()
                if q and a:
                    pairs.append((q, a))
        except Exception:
            pass
        return pairs

    def load_dataset(self) -> None:
        """Load static + custom Q&A and merge."""
        self.questions = []
        self.answers = []
        seen = set()
        for q, a in self._load_static_dataset() + self._load_custom_dataset():
            key = q.lower()
            if key not in seen:
                seen.add(key)
                self.questions.append(q)
                self.answers.append(a)
        if len(self.questions) != len(self.answers):
            self.answers = self.answers[: len(self.questions)]

    def train(self) -> None:
        """Build TF-IDF vectors for all questions."""
        if not self.questions:
            self.vectorizer = None
            self.question_vectors = None
            return
        self.vectorizer = TfidfVectorizer(
            lowercase=True,
            strip_accents="unicode",
            stop_words="english",
            ngram_range=(1, 2),
            max_features=8000,
        )
        self.question_vectors = self.vectorizer.fit_transform(self.questions)

    def _normalize(self, s: str) -> str:
        return re.sub(r"\s+", " ", s.strip().lower())

    def _normalize_query_for_matching(self, msg: str) -> str:
        """
        Expand common rephrasings and synonyms so similar Volt Guard questions
        map to the same intent/FAQ. Keeps word order but standardizes terms.
        """
        n = self._normalize(msg)
        # Replace common synonyms / paraphrases with canonical forms (for intent + FAQ)
        replacements = [
            (r"\b(usage|consumption|use|using)\b", "consumption"),
            (r"\b(cost|bill|pay|payment|spend|lkr|rupees)\b", "cost"),
            (r"\b(how much|how many|number of|count of|total)\b", "how many"),
            (r"\b(show|list|get|give me|tell me|display|see|check|find)\b", "show"),
            (r"\b(explain|describe|what is|whats|what's|define)\b", "explain"),
            (r"\b(energy|power|electricity|current)\b", "energy"),
            (r"\b(device|devices|appliance)\b", "device"),
            (r"\b(anomaly|anomalies|alert|alerts|unusual|abnormal)\b", "anomaly"),
            (r"\b(predict|prediction|forecast|forecasts|future)\b", "predict"),
            (r"\b(location|locations|zone|zones|room|rooms)\b", "location"),
            (r"\b(fault|faults|error|failure|problem|issue)\b", "fault"),
            (r"\b(dashboard|overview|summary|main screen)\b", "dashboard"),
            (r"\b(volt guard|voltage guard|voltageguard|voltguard)\b", "volt guard"),
            (r"\b(today|todays|current)\b", "today"),
            (r"\b(health|status|ok|problem|issue)\b", "status"),
        ]
        for pattern, canonical in replacements:
            n = re.sub(pattern, canonical, n, flags=re.IGNORECASE)
        return re.sub(r"\s+", " ", n).strip()

    @staticmethod
    def _parse_ts(raw: Any) -> Optional[datetime]:
        if raw is None:
            return None
        if isinstance(raw, datetime):
            return raw
        if isinstance(raw, str):
            try:
                return datetime.fromisoformat(raw.replace("Z", "+00:00"))
            except Exception:
                return None
        if isinstance(raw, dict) and "$date" in raw:
            return VoltGuardChatbot._parse_ts(raw["$date"])
        return None

    @staticmethod
    def _get_doc_timestamp(doc: Dict[str, Any]) -> Optional[datetime]:
        for field in ("received_at", "receivedAt", "timestamp", "created_at", "detected_at"):
            val = doc.get(field)
            ts = VoltGuardChatbot._parse_ts(val)
            if ts is not None:
                return ts
        return None

    @staticmethod
    def _extract_power_w(doc: Dict[str, Any]) -> float:
        if isinstance(doc.get("power_w"), (int, float)):
            return float(doc["power_w"])
        if isinstance(doc.get("current_a"), (int, float)):
            return float(doc["current_a"]) * VOLTAGE_DEFAULT
        if isinstance(doc.get("current_ma"), (int, float)):
            return float(doc["current_ma"]) / 1000.0 * VOLTAGE_DEFAULT
        return 0.0

    def _is_data_intent(self, msg: str) -> Optional[str]:
        """Detect intent from any Volt Guard system-related question. Uses word-pattern and synonym analysis for similar questions."""
        n = self._normalize(msg)
        if not n:
            return None
        # Use query normalization so rephrased/similar questions map to same intent
        qn = self._normalize_query_for_matching(msg)

        # System-wide analysis (check first so "analyze system" wins)
        system_phrases = [
            "analyze", "analysis", "overview", "entire system", "whole system",
            "system status", "system health", "how is my system", "voltage guard status",
            "volt guard status", "dashboard summary", "dashboard overview", "summary of",
            "tell me about my system", "system report", "full report", "everything about",
            "how are we doing", "status of my", "report on",
        ]
        # Check both raw normalized and query-normalized for broader pattern match
        def _has_any(text, phrases):
            return any(p in text for p in phrases)

        if _has_any(n, system_phrases) or _has_any(qn, system_phrases):
            return "system_analysis"
        if _has_any(n, ["dashboard", "overview"]) or _has_any(qn, ["dashboard", "overview"]):
            return "system_analysis"

        # Health / quick status
        if _has_any(n, ["health", "everything ok", "all good", "any problem", "any issue"]) or _has_any(qn, ["status"]):
            return "system_analysis"

        # Top consumers / highest power
        top_consumer_phrases = [
            "top consumer", "highest power", "most power", "which use most", "biggest consumer",
            "highest usage", "most energy", "top power", "who use most", "highest consumer",
        ]
        if _has_any(n, top_consumer_phrases) or _has_any(qn, top_consumer_phrases):
            return "top_consumers"

        # Devices (expand patterns for similar questions)
        device_phrases = [
            "how many device", "number of device", "list device", "all device",
            "devices?", "device list", "registered device", "device count",
            "total device", "show device", "list all device", "give me device",
            "my device", "device total", "how many dev", "what device", "which device",
            "device at", "devices at", "volt guard device", "how many device",
        ]
        if _has_any(n, device_phrases) or "device" in qn and ("show" in qn or "how many" in qn or "list" in qn):
            return "devices"

        # Energy
        energy_phrases = [
            "energy usage", "power usage", "current energy", "current power",
            "how much energy", "how much power", "energy consumption", "power consumption",
            "latest energy", "recent energy", "current usage", "energy now",
            "power now", "usage now", "consumption now", "my energy", "my power",
            "energy at", "power at", "usage at", "consumption at", "volt guard energy",
            "consumption", "usage",
        ]
        if _has_any(n, energy_phrases) or ("energy" in qn and ("show" in qn or "how much" in qn or "current" in qn)):
            return "energy" if " at " not in n else "energy_location"

        # Cost / bill / estimated monthly
        if _has_any(n, ["cost", "bill", "estimated monthly", "monthly cost", "how much pay", "lkr", "rupees", "tariff"]) or "cost" in qn:
            return "consumption_today"

        # Consumption today
        if _has_any(n, ["today", "consumption today", "usage today", "energy today", "how much today", "used today", "consumed today"]):
            if _has_any(n, ["energy", "power", "usage", "consumption", "used", "consumed", "how much", "kwh"]) or "today" in qn or len(n) < 25:
                return "consumption_today"

        # Predictions / forecast
        if _has_any(n, [
            "predict", "forecast", "prediction", "predicted", "future", "tomorrow", "next day",
            "forecast chart", "chart summary", "forecast summary", "chart", "forecast report",
        ]) or "predict" in qn:
            return "predictions"

        # Occupancy
        if _has_any(n, ["occupancy", "occupied", "who is in", "room occupied", "anyone in", "motion", "pir", "rcwl"]):
            return "occupancy"

        # Anomalies
        if _has_any(n, ["anomal", "alert", "unusual", "abnormal", "recent alert", "any alert"]) or "anomaly" in qn:
            return "anomalies"

        # Locations
        loc_phrases = [
            "location", "zone", "room", "where is monitor", "monitored location",
            "which location", "what location", "where are we", "which room",
            "list location", "all location", "monitored zone",
        ]
        if _has_any(n, loc_phrases) or "location" in qn and ("show" in qn or "list" in qn or "which" in qn):
            return "locations"

        # Faults
        if _has_any(n, ["fault", "failure", "device health", "error", "device error"]) or "fault" in qn:
            return "faults"

        # Volt Guard general question → system analysis
        if "volt guard" in n or "voltage guard" in n or "voltageguard" in n or "volt guard" in qn:
            if _has_any(n, ["what", "how", "tell", "explain", "status", "system", "data"]) or "explain" in qn or "status" in qn:
                return "system_analysis"
        return None

    def _build_system_analysis(self) -> str:
        """Analyse entire Volt Guard system from all database tables and return a summary."""
        lines = ["📊 Volt Guard system analysis (from your database):\n"]
        try:
            # Devices
            devices = list(self._devices_col.find({}, {"_id": 0, "device_id": 1, "device_name": 1, "location": 1, "rated_power_watts": 1}))
            dev_count = len(devices)
            total_rated = sum(d.get("rated_power_watts") or 0 for d in devices)
            lines.append(f"• Devices: {dev_count} registered, total rated {total_rated} W")

            # Locations
            locs = set(d.get("location") for d in devices if d.get("location"))
            for doc in self._energy_col.find({}, {"location": 1}).limit(200):
                if doc.get("location"):
                    locs.add(doc["location"])
            lines.append(f"• Locations: {len(locs)} ({', '.join(sorted(locs)[:5])}{'...' if len(locs) > 5 else ''})")

            # Today's consumption
            today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
            today_readings = list(self._energy_col.find({"$or": [{"received_at": {"$gte": today_start}}, {"receivedAt": {"$gte": today_start}}]}, {"_id": 0}).limit(5000))
            today_kwh = 0.0
            if today_readings:
                points = []
                for r in today_readings:
                    ts = self._get_doc_timestamp(r)
                    if ts:
                        points.append({"ts": ts, "power_w": self._extract_power_w(r)})
                points.sort(key=lambda x: x["ts"])
                for i in range(1, len(points)):
                    dt_s = (points[i]["ts"] - points[i - 1]["ts"]).total_seconds()
                    if 0 < dt_s <= 900:
                        avg_w = (points[i - 1]["power_w"] + points[i]["power_w"]) / 2.0
                        today_kwh += avg_w * (dt_s / 3600.0) / 1000.0
            cost_today = _kwh_to_lkr(today_kwh, 1.0)
            lines.append(f"• Today's consumption: {today_kwh:.2f} kWh (LKR {cost_today:.0f}, CEB tariff)")

            # Latest power by location (top consumers)
            latest = list(self._energy_col.find({}, {"_id": 0}).sort("received_at", -1).limit(200))
            by_loc: Dict[str, float] = {}
            for r in latest:
                loc = r.get("location") or r.get("module") or "Unknown"
                pw = self._extract_power_w(r)
                by_loc[loc] = max(by_loc.get(loc, 0), pw)
            if by_loc:
                top = sorted(by_loc.items(), key=lambda x: -x[1])[:5]
                lines.append(f"• Top power now: {', '.join(f'{loc}={w:.0f}W' for loc, w in top)}")

            # Anomalies (7d)
            since = datetime.utcnow() - timedelta(hours=168)
            try:
                anom_count = self._anomaly_col.count_documents({"detected_at": {"$gte": since.isoformat()}})
            except Exception:
                anom_count = self._anomaly_col.count_documents({"detected_at": {"$gte": since}})
            lines.append(f"• Anomalies (7 days): {anom_count}")

            # Faults
            fault_count = 0
            if getattr(self, "_faults_col", None) is not None:
                try:
                    fault_count = self._faults_col.count_documents({"detected_at": {"$gte": since.isoformat()}})
                except Exception:
                    try:
                        fault_count = self._faults_col.count_documents({"detected_at": {"$gte": since}})
                    except Exception:
                        pass
                lines.append(f"• Faults (7 days): {fault_count}")
            else:
                lines.append("• Faults: N/A")

            # Predictions
            if getattr(self, "_prediction_col", None) is not None:
                preds = list(self._prediction_col.find({"prediction_type": "daily"}, {"_id": 0}).limit(50))
                pred_kwh = sum(p.get("predicted_energy_kwh") or 0 for p in preds)
                lines.append(f"• Predictions: {len(preds)} entries, {pred_kwh:.1f} kWh total predicted")
            else:
                lines.append("• Predictions: N/A")

            # Occupancy
            pipeline = [{"$sort": {"received_at": -1}}, {"$group": {"_id": "$location", "doc": {"$first": "$$ROOT"}}}]
            grouped = list(self._analytics_col.aggregate(pipeline))
            occupied = sum(
                1 for g in grouped
                if (g.get("doc") or {}).get("rcwl") or (g.get("doc") or {}).get("pir")
            )
            lines.append(f"• Occupancy: {occupied}/{len(grouped)} locations occupied (latest)")

            # Health verdict
            if anom_count > 0 or (getattr(self, "_faults_col", None) is not None and fault_count > 0):
                lines.append("\n⚠️ Attention: anomalies or faults detected. Check Anomalies/Faults for details.")
            else:
                lines.append("\n✅ System healthy. No recent anomalies or faults.")
        except Exception as e:
            lines.append(f"\nError reading some data: {e}")
        return "\n".join(lines)

    def _answer_from_data(self, msg: str) -> Optional[str]:
        """Query DB and return an answer string using real table data."""
        if not self._db:
            return None
        intent = self._is_data_intent(msg)
        if not intent:
            return None
        try:
            if intent == "system_analysis":
                return self._build_system_analysis()

            if intent == "top_consumers":
                latest = list(self._energy_col.find({}, {"_id": 0}).sort("received_at", -1).limit(300))
                by_loc: Dict[str, List[float]] = {}
                for r in latest:
                    loc = r.get("location") or r.get("module") or "Unknown"
                    pw = self._extract_power_w(r)
                    by_loc.setdefault(loc, []).append(pw)
                if not by_loc:
                    return "No energy data yet. Top consumers will appear once readings are available."
                avg_by_loc = [(loc, sum(v) / len(v)) for loc, v in by_loc.items()]
                top = sorted(avg_by_loc, key=lambda x: -x[1])[:8]
                lines = ["Top power consumers (from recent database readings):\n"]
                for i, (loc, avg_w) in enumerate(top, 1):
                    lines.append(f"  {i}. {loc}: {avg_w:.1f} W avg")
                return "\n".join(lines)

            if intent == "devices":
                devices = list(self._devices_col.find({}, {"_id": 0}))
                count = len(devices)
                if count == 0:
                    return "You have no devices registered yet. Add devices from the Devices page to start monitoring."
                lines = [f"You have {count} device(s) in the database:\n"]
                for d in devices[:15]:
                    name = d.get("device_name") or d.get("device_id") or "Device"
                    loc = d.get("location") or "—"
                    dtype = d.get("device_type") or "—"
                    rated = d.get("rated_power_watts")
                    relay = d.get("relay_state") or "—"
                    line = f"• {name} ({dtype}) @ {loc}"
                    if rated is not None:
                        line += f", {rated} W"
                    line += f", relay {relay}"
                    lines.append(line)
                if count > 15:
                    lines.append(f"\n... and {count - 15} more.")
                return "\n".join(lines)

            if intent == "energy" or intent == "energy_location":
                latest = list(
                    self._energy_col.find({}, {"_id": 0})
                    .sort("received_at", -1)
                    .limit(80)
                )
                if not latest:
                    return "No energy readings in the database yet. Data will appear once devices report readings."
                by_loc: Dict[str, Dict] = {}
                for r in latest:
                    loc = r.get("location") or r.get("module") or "Unknown"
                    if loc not in by_loc:
                        by_loc[loc] = r
                lines = ["Latest energy (real data from database):\n"]
                for loc, r in list(by_loc.items())[:12]:
                    pw = self._extract_power_w(r)
                    ts = self._get_doc_timestamp(r)
                    ts_str = ts.strftime("%Y-%m-%d %H:%M") if ts else "?"
                    if pw > 0:
                        lines.append(f"• {loc}: {pw:.1f} W at {ts_str}")
                    else:
                        lines.append(f"• {loc}: at {ts_str}")
                return "\n".join(lines)

            if intent == "consumption_today":
                today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
                readings = list(
                    self._energy_col.find(
                        {"$or": [
                            {"received_at": {"$gte": today_start}},
                            {"receivedAt": {"$gte": today_start}},
                            {"timestamp": {"$gte": today_start}},
                        ]},
                        {"_id": 0},
                    ).limit(5000)
                )
                if not readings:
                    return "No energy readings for today yet. Data will appear as devices report."
                points = []
                for r in readings:
                    ts = self._get_doc_timestamp(r)
                    if ts is None:
                        continue
                    pw = self._extract_power_w(r)
                    points.append({"ts": ts, "power_w": pw})
                points.sort(key=lambda x: x["ts"])
                total_kwh = 0.0
                for i in range(1, len(points)):
                    dt_s = (points[i]["ts"] - points[i - 1]["ts"]).total_seconds()
                    if dt_s <= 0 or dt_s > 900:
                        dt_s = min(dt_s if dt_s > 0 else 30, 900)
                    avg_w = (points[i - 1]["power_w"] + points[i]["power_w"]) / 2.0
                    total_kwh += avg_w * (dt_s / 3600.0) / 1000.0
                avg_w = sum(p["power_w"] for p in points) / len(points) if points else 0
                peak_w = max(p["power_w"] for p in points) if points else 0
                # CEB tariff: prorate today's kWh to monthly then apply block tariff
                cost_lkr = _kwh_to_lkr(total_kwh, 1.0)
                # If today continues: projected monthly kWh and cost
                hours_elapsed = (datetime.utcnow() - today_start).total_seconds() / 3600.0 or 1.0
                rate_today = total_kwh / hours_elapsed if hours_elapsed > 0 else 0
                projected_monthly_kwh = rate_today * 24 * 30 if rate_today > 0 else 0
                projected_lkr = _calculate_monthly_lkr(projected_monthly_kwh) if projected_monthly_kwh > 0 else 0
                lines = [
                    "Today's consumption (real data):",
                    f"• Readings: {len(points)}",
                    f"• Total: {total_kwh:.2f} kWh",
                    f"• Average power: {avg_w:.1f} W | Peak: {peak_w:.1f} W",
                    f"• Est. cost today (CEB tariff): LKR {cost_lkr:.0f}",
                ]
                if projected_monthly_kwh > 0:
                    lines.append(f"• If this rate continues: ~{projected_monthly_kwh:.0f} kWh/month, ~LKR {projected_lkr:.0f}/month")
                return "\n".join(lines)

            if intent == "anomalies":
                since = datetime.utcnow() - timedelta(hours=168)
                since_str = since.isoformat()
                try:
                    count = self._anomaly_col.count_documents({"detected_at": {"$gte": since_str}})
                except Exception:
                    try:
                        count = self._anomaly_col.count_documents({"detected_at": {"$gte": since}})
                    except Exception:
                        count = self._anomaly_col.count_documents({"created_at": {"$gte": since}})
                recent = list(
                    self._anomaly_col.find({}, {"_id": 0})
                    .sort("detected_at", -1)
                    .limit(10)
                )
                if count == 0 and not recent:
                    return "No anomalies in the last 7 days. Your energy data looks normal."
                lines = [f"Anomalies (last 7 days): {count} found.\n\nRecent from database:"]
                for a in recent[:6]:
                    dev_id = a.get("device_id") or a.get("location") or "?"
                    device = self._devices_col.find_one({"device_id": dev_id}, {"_id": 0, "device_name": 1}) if dev_id != "?" else None
                    name = (device.get("device_name") or dev_id) if device else dev_id
                    sev = a.get("severity") or "—"
                    desc = a.get("message") or a.get("description") or "Anomaly detected"
                    lines.append(f"• {name} ({sev}): {str(desc)[:55]}")
                return "\n".join(lines)

            if intent == "predictions":
                preds = []
                if getattr(self, "_prediction_col", None) is not None:
                    preds = list(
                        self._prediction_col.find({"prediction_type": "daily"}, {"_id": 0})
                        .sort("created_at", -1)
                        .limit(20)
                    )
                if not preds:
                    return (
                        "No forecast/prediction data in the database yet. "
                        "Run predictions from the app (Dashboard or Prediction API) to see your forecast chart summary here."
                    )
                total_kwh = sum(p.get("predicted_energy_kwh") or 0 for p in preds)
                conf = [p.get("confidence_score") for p in preds if p.get("confidence_score") is not None]
                avg_conf = (sum(conf) / len(conf)) * 100 if conf else 0
                lines = [
                    "Forecast chart summary (from your database):",
                    f"• Total predicted energy: {total_kwh:.2f} kWh",
                    f"• Entries: {len(preds)}",
                    f"• Average confidence: {avg_conf:.0f}%",
                    "",
                    "By location:",
                ]
                for p in preds[:8]:
                    loc = p.get("location") or p.get("module") or "—"
                    kwh = p.get("predicted_energy_kwh") or 0
                    lines.append(f"  • {loc}: {kwh:.2f} kWh")
                return "\n".join(lines)

            if intent == "occupancy":
                pipeline = [
                    {"$sort": {"received_at": -1}},
                    {"$group": {"_id": "$location", "doc": {"$first": "$$ROOT"}}},
                ]
                grouped = list(self._analytics_col.aggregate(pipeline))
                if not grouped:
                    return "No occupancy/telemetry data in the database yet."
                lines = ["Occupancy (latest per location from database):\n"]
                for g in grouped[:12]:
                    doc = g.get("doc") or {}
                    loc = g.get("_id") or doc.get("location") or "?"
                    rcwl = doc.get("rcwl", 0)
                    pir = doc.get("pir", 0)
                    occ = "Occupied" if (rcwl or pir) else "Empty"
                    temp = doc.get("temperature")
                    hum = doc.get("humidity")
                    line = f"• {loc}: {occ}"
                    if temp is not None:
                        line += f", {temp}°C"
                    if hum is not None:
                        line += f", {hum}% humidity"
                    lines.append(line)
                return "\n".join(lines)

            if intent == "locations":
                locs_from_devices: Dict[str, int] = {}
                for d in self._devices_col.find({}, {"location": 1}):
                    loc = d.get("location")
                    if loc:
                        locs_from_devices[str(loc)] = locs_from_devices.get(str(loc), 0) + 1
                for doc in self._energy_col.find({}, {"location": 1}).limit(500):
                    loc = doc.get("location")
                    if loc:
                        locs_from_devices.setdefault(str(loc), 0)
                locs = sorted(locs_from_devices.keys())
                if not locs:
                    return "No location data in the database yet. Add devices or wait for telemetry."
                lines = ["Monitored locations (from devices & energy data):\n"]
                for loc in locs[:25]:
                    c = locs_from_devices.get(loc, 0)
                    lines.append(f"• {loc}: {c} device(s)" if c else f"• {loc}")
                return "\n".join(lines)

            if intent == "faults":
                if getattr(self, "_faults_col", None) is None:
                    return "Fault data is not available."
                recent = list(
                    self._faults_col.find({}, {"_id": 0})
                    .sort("detected_at", -1)
                    .limit(10)
                )
                if not recent:
                    return "No faults in the database. Device health looks good."
                lines = [f"Faults (from database): {len(recent)} recent.\n"]
                for f in recent[:6]:
                    dev = f.get("device_id") or f.get("location") or "?"
                    sev = f.get("severity") or "—"
                    desc = f.get("description") or f.get("message") or "—"
                    lines.append(f"• {dev} ({sev}): {str(desc)[:50]}")
                return "\n".join(lines)
        except Exception as e:
            return f"I couldn't read the database right now: {e}. Please try again later."
        return None

    def get_response(
        self, user_message: str, threshold: float = 0.2, top_k: int = 1
    ) -> Tuple[str, float, List[str]]:
        """
        Return (answer, confidence, suggestions).
        First tries DB data answer, then FAQ (TF-IDF). Always returns suggestions.
        """
        msg = user_message.strip()
        suggestions = self.get_suggestions(limit=4, last_message=msg)

        if not msg:
            return self._fallback(), 0.0, suggestions

        # 1) Try live data answer
        data_answer = self._answer_from_data(msg)
        if data_answer:
            return data_answer, 0.95, suggestions

        # 2) Normal/FAQ from dataset: match on normalized + query-normalized form for similar questions
        if self.question_vectors is not None and self.vectorizer is not None:
            normalized_msg = self._normalize(msg)
            query_normalized = self._normalize_query_for_matching(msg)
            # Try both forms so rephrased questions still match
            for text_to_try in [query_normalized, normalized_msg]:
                q_vec = self.vectorizer.transform([text_to_try])
                sim = cosine_similarity(q_vec, self.question_vectors)[0]
                top_idx = np.argsort(sim)[::-1][:max(top_k, 3)]
                best_sim = float(sim[top_idx[0]])
                # Lower threshold for Volt Guard–related so similar questions get correct answers
                use_threshold = threshold
                volt_guard_words = ["volt", "guard", "dashboard", "system", "device", "energy", "anomal", "predict", "location", "consumption", "cost", "fault"]
                if any(w in normalized_msg for w in volt_guard_words) or any(w in query_normalized for w in volt_guard_words):
                    use_threshold = min(threshold, 0.15)
                if best_sim >= use_threshold:
                    return self.answers[top_idx[0]], best_sim, suggestions
        return self._fallback(), 0.0, suggestions

    def _fallback(self) -> str:
        return (
            "I'm the Volt Guard assistant. I can answer using your live data (devices, energy, anomalies, locations) "
            "or general questions about the app. Try: \"How many devices do I have?\", \"What is my current energy usage?\", "
            "\"Explain the dashboard\", or add your own Q&A in Update dataset."
        )

    def get_suggestions(self, limit: int = 4, last_message: Optional[str] = None) -> List[str]:
        """Return suggestions; when last_message is set, return follow-ups related to that question."""
        if last_message and last_message.strip():
            intent = self._is_data_intent(last_message.strip())
            if intent and intent in FOLLOW_UP_BY_INTENT:
                return FOLLOW_UP_BY_INTENT[intent][:limit]
        out: List[str] = []
        seen = set()
        for q in DEFAULT_SUGGESTIONS:
            if len(out) >= limit:
                break
            n = self._normalize(q)
            if n not in seen:
                seen.add(n)
                out.append(q)
        for q in (self.questions or [])[:20]:
            if len(out) >= limit:
                break
            n = self._normalize(q)
            if n not in seen and len(q) < 60:
                seen.add(n)
                out.append(q)
        return out[:limit]

    def add_custom_qa(self, question: str, answer: str) -> Dict[str, Any]:
        """Add a custom Q&A to MongoDB and reload dataset."""
        q, a = question.strip(), answer.strip()
        if not q or not a:
            return {"ok": False, "error": "Question and answer are required"}
        if self._db is not True or getattr(self, "_chatbot_custom_qa_col", None) is None:
            return {"ok": False, "error": "Database not available"}
        try:
            getattr(self, "_chatbot_custom_qa_col", None).insert_one({
                "question": q,
                "answer": a,
                "created_at": datetime.utcnow(),
            })
            self.load_dataset()
            self.train()
            return {"ok": True, "message": "Added successfully. The chatbot will use this from now on."}
        except Exception as e:
            return {"ok": False, "error": str(e)}

    def list_custom_qa(self) -> List[Dict[str, Any]]:
        """List custom Q&A entries from MongoDB."""
        col = getattr(self, "_chatbot_custom_qa_col", None)
        if self._db is not True or col is None:
            return []
        out = []
        for doc in col.find().sort("created_at", -1):
            out.append({
                "id": str(doc["_id"]),
                "question": doc.get("question", ""),
                "answer": doc.get("answer", ""),
                "created_at": doc.get("created_at"),
            })
        return out

    def delete_custom_qa(self, entry_id: str) -> Dict[str, Any]:
        """Delete a custom Q&A by id and reload."""
        col = getattr(self, "_chatbot_custom_qa_col", None)
        if self._db is not True or col is None:
            return {"ok": False, "error": "Database not available"}
        try:
            from bson import ObjectId
            col.delete_one({"_id": ObjectId(entry_id)})
            self.load_dataset()
            self.train()
            return {"ok": True, "message": "Deleted."}
        except Exception as e:
            return {"ok": False, "error": str(e)}


_chatbot_instance: Optional[VoltGuardChatbot] = None


def get_chatbot() -> VoltGuardChatbot:
    """Get or create the singleton chatbot."""
    global _chatbot_instance
    if _chatbot_instance is None:
        _chatbot_instance = VoltGuardChatbot()
        _chatbot_instance.load_dataset()
        _chatbot_instance.train()
    return _chatbot_instance


def reset_chatbot() -> None:
    """Force reload (e.g. after adding custom Q&A from another process)."""
    global _chatbot_instance
    _chatbot_instance = None
