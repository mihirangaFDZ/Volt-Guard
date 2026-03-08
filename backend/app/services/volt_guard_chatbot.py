"""
Volt Guard AI Chatbot - answers from database data + FAQ dataset (static + custom).
Uses TF-IDF for FAQ; queries MongoDB for live data (devices, energy, anomalies, etc.).
Returns suggestions to guide the user. Supports adding/updating custom Q&A.
"""

import json
import os
import re
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity


def _default_dataset_path() -> str:
    base = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return os.path.join(base, "volt_guard_dataset.json")


# Suggested questions (max 4 shown in UI)
DEFAULT_SUGGESTIONS = [
    "How many devices do I have?",
    "What is my current energy usage?",
    "Any recent anomalies?",
    "What locations are monitored?",
]


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
                )
                self._devices_col = devices_col
                self._energy_col = energy_col
                self._anomaly_col = anomaly_col
                self._analytics_col = analytics_col
                self._chatbot_custom_qa_col = chatbot_custom_qa_col
                self._faults_col = faults_col
                self._db = True
            except Exception:
                self._db = None
                self._faults_col = None

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
        if not self._db or not self._chatbot_custom_qa_col:
            return pairs
        try:
            for doc in self._chatbot_custom_qa_col.find({}, {"_id": 0, "question": 1, "answer": 1}):
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

    def _is_data_intent(self, msg: str) -> Optional[str]:
        """Detect if user is asking for live data (case-insensitive). Return intent key or None."""
        n = self._normalize(msg)
        if not n:
            return None
        # Devices (case-insensitive via n)
        device_phrases = [
            "how many device", "number of device", "list device", "all device",
            "devices?", "device list", "registered device", "device count",
            "total device", "show device", "list all device", "give me device",
            "my device", "device total", "how many dev",
        ]
        if any(w in n for w in device_phrases):
            return "devices"
        if any(w in n for w in ["which device", "what device", "device at", "devices at"]):
            return "devices_list"
        # Energy
        energy_phrases = [
            "energy usage", "power usage", "current energy", "current power",
            "how much energy", "how much power", "energy consumption", "power consumption",
            "latest energy", "recent energy", "current usage", "energy now",
            "power now", "usage now", "consumption now", "my energy", "my power",
        ]
        if any(w in n for w in energy_phrases):
            return "energy"
        if any(w in n for w in ["energy at", "power at", "usage at", "consumption at"]):
            return "energy_location"
        # Anomalies
        if any(w in n for w in ["anomal", "alert", "unusual", "abnormal", "recent alert", "any alert"]):
            return "anomalies"
        # Locations / zones
        loc_phrases = [
            "location", "zone", "room", "where is monitor", "monitored location",
            "which location", "what location", "where are we", "which room",
            "list location", "all location", "monitored zone",
        ]
        if any(w in n for w in loc_phrases):
            return "locations"
        # Faults
        if any(w in n for w in ["fault", "failure", "device health", "error", "device error"]):
            return "faults"
        return None

    def _answer_from_data(self, msg: str) -> Optional[str]:
        """Query DB and return an answer string, or None if not applicable."""
        if not self._db:
            return None
        intent = self._is_data_intent(msg)
        if not intent:
            return None
        try:
            if intent == "devices" or intent == "devices_list":
                devices = list(self._devices_col.find({}, {"_id": 0, "device_id": 1, "location": 1, "module_id": 1}))
                count = len(devices)
                if count == 0:
                    return "You have no devices registered yet. Add devices from the Devices page to start monitoring."
                locs = {}
                for d in devices:
                    loc = d.get("location") or "Unknown"
                    locs[loc] = locs.get(loc, 0) + 1
                loc_lines = [f"• {loc}: {c} device(s)" for loc, c in sorted(locs.items())]
                return f"You have {count} device(s) total.\n\nBy location:\n" + "\n".join(loc_lines)

            if intent == "energy" or intent == "energy_location":
                latest = list(
                    self._energy_col.find({}, {"_id": 0, "location": 1, "module": 1, "current_a": 1, "power_w": 1, "received_at": 1})
                    .sort("received_at", -1)
                    .limit(50)
                )
                if not latest:
                    return "No energy readings in the database yet. Data will appear once devices report readings."
                # Group by location/module for summary
                by_loc: Dict[str, List[Dict]] = {}
                for r in latest:
                    loc = r.get("location") or r.get("module") or "Unknown"
                    if loc not in by_loc:
                        by_loc[loc] = []
                    by_loc[loc].append(r)
                lines = []
                for loc, rows in by_loc.items():
                    r0 = rows[0]
                    p = r0.get("power_w")
                    a = r0.get("current_a")
                    ts = r0.get("received_at")
                    ts_str = str(ts)[:19] if ts else "?"
                    if p is not None:
                        lines.append(f"• {loc}: {float(p):.2f} W (at {ts_str})")
                    elif a is not None:
                        lines.append(f"• {loc}: {float(a):.3f} A current (at {ts_str})")
                    else:
                        lines.append(f"• {loc}: latest at {ts_str}")
                return "Latest energy data:\n\n" + "\n".join(lines[:15])

            if intent == "anomalies":
                since = datetime.utcnow() - timedelta(hours=168)
                count = self._anomaly_col.count_documents({"created_at": {"$gte": since}})
                recent = list(
                    self._anomaly_col.find(
                        {"created_at": {"$gte": since}},
                        {"_id": 0, "device_id": 1, "location": 1, "severity": 1, "created_at": 1, "message": 1},
                    )
                    .sort("created_at", -1)
                    .limit(10)
                )
                if count == 0:
                    return "No anomalies in the last 7 days. Your energy data looks normal."
                lines = [f"Found {count} anomaly/alert(s) in the last 7 days. Recent:"]
                for a in recent[:5]:
                    dev = a.get("device_id") or a.get("location") or "?"
                    sev = a.get("severity") or "—"
                    msg = (a.get("message") or "")[:60]
                    lines.append(f"• {dev} ({sev}): {msg}")
                return "\n".join(lines)

            if intent == "locations":
                # From analytics (occupancy_telemetry) or energy
                locs_analytics = set()
                for doc in self._analytics_col.find({}, {"location": 1}).limit(500):
                    loc = doc.get("location")
                    if loc:
                        locs_analytics.add(str(loc))
                for doc in self._energy_col.find({}, {"location": 1}).limit(500):
                    loc = doc.get("location")
                    if loc:
                        locs_analytics.add(str(loc))
                locs = sorted(locs_analytics)
                if not locs:
                    return "No location data in the database yet. Locations appear when devices or telemetry report a location."
                return "Monitored locations:\n\n" + "\n".join(f"• {loc}" for loc in locs[:30])

            if intent == "faults":
                if not getattr(self, "_faults_col", None):
                    return "Fault data is not available."
                recent = list(self._faults_col.find({}, {"_id": 0}).sort("created_at", -1).limit(10))
                if not recent:
                    return "No faults recorded. Device health looks good."
                lines = [f"Found {len(recent)} recent fault(s):"]
                for f in recent[:5]:
                    dev = f.get("device_id") or f.get("location") or "?"
                    lines.append(f"• {dev}: {f.get('description', f.get('message', '—'))[:50]}")
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
        if not msg:
            return self._fallback(), 0.0, self.get_suggestions()

        # 1) Try live data answer
        data_answer = self._answer_from_data(msg)
        if data_answer:
            return data_answer, 0.95, self.get_suggestions()

        # 2) Normal/FAQ from dataset (case-insensitive: normalize for matching)
        if self.question_vectors is not None and self.vectorizer is not None:
            normalized_msg = self._normalize(msg)
            q_vec = self.vectorizer.transform([normalized_msg])
            sim = cosine_similarity(q_vec, self.question_vectors)[0]
            top_idx = np.argsort(sim)[::-1][:top_k]
            best_sim = float(sim[top_idx[0]])
            if best_sim >= threshold:
                return self.answers[top_idx[0]], best_sim, self.get_suggestions()
        return self._fallback(), 0.0, self.get_suggestions()

    def _fallback(self) -> str:
        return (
            "I'm the Volt Guard assistant. I can answer using your live data (devices, energy, anomalies, locations) "
            "or general questions about the app. Try: \"How many devices do I have?\", \"What is my current energy usage?\", "
            "\"Explain the dashboard\", or add your own Q&A in Update dataset."
        )

    def get_suggestions(self, limit: int = 4) -> List[str]:
        """Return suggested questions to guide the user."""
        out: List[str] = []
        seen = set()
        for q in DEFAULT_SUGGESTIONS:
            if q not in seen and len(out) < limit:
                seen.add(self._normalize(q))
                out.append(q)
        # Add a few from dataset (variety)
        for q in (self.questions or [])[:20]:
            n = self._normalize(q)
            if n not in seen and len(q) < 60 and len(out) < limit:
                seen.add(n)
                out.append(q)
        return out[:limit]

    def add_custom_qa(self, question: str, answer: str) -> Dict[str, Any]:
        """Add a custom Q&A to MongoDB and reload dataset."""
        q, a = question.strip(), answer.strip()
        if not q or not a:
            return {"ok": False, "error": "Question and answer are required"}
        if not self._db or not self._chatbot_custom_qa_col:
            return {"ok": False, "error": "Database not available"}
        try:
            self._chatbot_custom_qa_col.insert_one({
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
        if not self._db or not self._chatbot_custom_qa_col:
            return []
        out = []
        for doc in self._chatbot_custom_qa_col.find().sort("created_at", -1):
            out.append({
                "id": str(doc["_id"]),
                "question": doc.get("question", ""),
                "answer": doc.get("answer", ""),
                "created_at": doc.get("created_at"),
            })
        return out

    def delete_custom_qa(self, entry_id: str) -> Dict[str, Any]:
        """Delete a custom Q&A by id and reload."""
        if not self._db or not self._chatbot_custom_qa_col:
            return {"ok": False, "error": "Database not available"}
        try:
            from bson import ObjectId
            self._chatbot_custom_qa_col.delete_one({"_id": ObjectId(entry_id)})
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
