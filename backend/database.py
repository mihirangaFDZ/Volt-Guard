from pathlib import Path
from pymongo import MongoClient
from pymongo.server_api import ServerApi
import os
from dotenv import load_dotenv

# Get the directory where this file (database.py) is located
BASE_DIR = Path(__file__).resolve().parent

# Load .env file from the backend directory
load_dotenv(dotenv_path=BASE_DIR / '.env')

# Configure MongoDB client with proper timeout and DNS settings
client = MongoClient(
    os.getenv("MONGO_URI"),
    server_api=ServerApi('1'),
    serverSelectionTimeoutMS=5000,  # 5 second timeout
    connectTimeoutMS=10000,  # 10 second connection timeout
    socketTimeoutMS=10000,   # 10 second socket timeout
    retryWrites=True,
    retryReads=True,
    maxPoolSize=10,
    minPoolSize=1
)
db = client[os.getenv("MONGODB_DB_NAME")]

devices_col = db["devices"]
energy_col = db["energy_readings"]
prediction_col = db["predictions"]
anomaly_col = db["anomalies"]
user_col = db["users"]
analytics_col = db["occupancy_telemetry"]
faults_col = db["faults"]

# Uniqueness and query performance indexes
def _safe_create_index(collection, keys, **kwargs):
    try:
        collection.create_index(keys, **kwargs)
    except Exception:
        pass


_safe_create_index(user_col, "user_id", unique=True)
_safe_create_index(user_col, "email", unique=True)

_safe_create_index(devices_col, [("owner_user_id", 1), ("device_id", 1)], unique=True)
_safe_create_index(
    devices_col,
    "module_id",
    unique=True,
    partialFilterExpression={"module_id": {"$exists": True}},
)

_safe_create_index(energy_col, "owner_user_id")
_safe_create_index(prediction_col, "owner_user_id")
_safe_create_index(anomalies_col, "owner_user_id")
_safe_create_index(analytics_col, "owner_user_id")
_safe_create_index(faults_col, "owner_user_id")
