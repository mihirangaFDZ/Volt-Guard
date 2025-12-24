from pathlib import Path
from pymongo import MongoClient
import os
from dotenv import load_dotenv

# Get the directory where this file (database.py) is located
BASE_DIR = Path(__file__).resolve().parent

# Load .env file from the backend directory
load_dotenv(dotenv_path=BASE_DIR / '.env')

client = MongoClient(os.getenv("MONGO_URI"))
db = client[os.getenv("MONGODB_DB_NAME")]

devices_col = db["devices"]
energy_col = db["energy_readings"]
prediction_col = db["predictions"]
anomaly_col = db["anomalies"]
user_col = db["users"]
