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
# Increased timeouts to avoid NetworkTimeout on slow/latent connections (e.g. Atlas over internet)
client = MongoClient(
    os.getenv("MONGO_URI"),
    server_api=ServerApi('1'),
    serverSelectionTimeoutMS=20000,  # 20s to select server
    connectTimeoutMS=20000,          # 20s to connect
    socketTimeoutMS=30000,           # 30s for read/write operations
    retryWrites=True,
    retryReads=True,
    maxPoolSize=10,
    minPoolSize=1,
)
db = client[os.getenv("MONGODB_DB_NAME")]

devices_col = db["devices"]
energy_col = db["energy_readings"]
prediction_col = db["predictions"]
anomaly_col = db["anomalies"]
user_col = db["users"]
analytics_col = db["occupancy_telemetry"]
faults_col = db["faults"]
chatbot_custom_qa_col = db["chatbot_custom_qa"]
bills_col = db["bills"]
