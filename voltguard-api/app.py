import os
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, request, jsonify
from pymongo import MongoClient
from dotenv import load_dotenv

# Always load the .env that sits next to this file, no matter the CWD
BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

# Accept either MONGO_URI_API or legacy MONGO_URI
MONGO_URI = os.getenv("MONGO_URI_API") or os.getenv("MONGO_URI")
API_KEY = os.getenv("API_KEY")
DB_NAME = os.getenv("DB_NAME", "volt_guard")
COLLECTION_NAME = os.getenv("COLLECTION_NAME", "occupancy_telemetry")

if not MONGO_URI:
    raise RuntimeError("MONGO_URI_API or MONGO_URI is not set")
if not API_KEY:
    raise RuntimeError("API_KEY is not set")

app = Flask(__name__)

client = MongoClient(MONGO_URI)
db = client[DB_NAME]
collection = db[COLLECTION_NAME]


@app.get("/health")
def health():
    return jsonify({"ok": True})


@app.post("/api/v1/telemetry")
def telemetry():
    # --- Simple authentication ---
    if request.headers.get("X-API-Key") != API_KEY:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    # --- Parse JSON ---
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"ok": False, "error": "invalid JSON body"}), 400

    # --- Minimal validation (adjust to your needs) ---
    required = ["module", "location", "rcwl", "pir"]
    missing = [k for k in required if k not in data]
    if missing:
        return jsonify({"ok": False, "error": f"missing fields: {missing}"}), 400

    doc = {
        **data,
        "received_at": datetime.now(timezone.utc),
        "source": "esp8266",
    }

    result = collection.insert_one(doc)
    return jsonify({"ok": True, "id": str(result.inserted_id)}), 201


if __name__ == "__main__":
    # Local dev server
    app.run(host="0.0.0.0", port=5000, debug=True)