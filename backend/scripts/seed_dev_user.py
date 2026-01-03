from dotenv import load_dotenv
import os
from pathlib import Path
from pymongo import MongoClient
import certifi
import bcrypt

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / '.env')

mongo_url = os.getenv('MONGODB_URL')
db_name = os.getenv('MONGODB_DB_NAME', 'voltguard')

client = MongoClient(mongo_url, tlsCAFile=certifi.where())
db = client[db_name]
users = db['users']

email = 'demo@voltguard.local'
existing = users.find_one({'email': email})
if existing:
    print('User already exists:', existing.get('email'))
else:
    user_doc = {
        'user_id': 'demo-001',
        'name': 'Demo User',
        'email': email,
        'role': 'user',
        'created_at': None,
        'password': bcrypt.hashpw(b'demo123', bcrypt.gensalt()).decode('utf-8'),
    }
    users.insert_one(user_doc)
    print('Seeded user:', email)
