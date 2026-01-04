from pathlib import Path
from pymongo import MongoClient
from pymongo.server_api import ServerApi
import certifi
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
    minPoolSize=1,
    tlsCAFile=certifi.where() 
)
db = client[os.getenv("MONGODB_DB_NAME")]

devices_col = db["devices"]
energy_col = db["energy_readings"]
prediction_col = db["predictions"]
anomaly_col = db["anomalies"]
user_col = db["users"]
analytics_col = db["occupancy_telemetry"]
