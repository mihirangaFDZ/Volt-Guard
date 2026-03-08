# Volt Guard
## Smart Energy Management System Using IoT and AI-Based Data Analytics

Volt Guard is an advanced AI-powered energy management system that analyzes energy consumption data from IoT devices, predicts future energy usage using machine learning models, detects abnormal consumption patterns, and identifies potential faults in appliances in real-time.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Model Training](#model-training)
3. [Features](#features)
4. [Architecture](#architecture)
5. [Technology Stack](#technology-stack)
6. [Dependencies](#dependencies)
7. [Getting Started](#getting-started)
8. [Project Structure](#project-structure)
9. [API Documentation](#api-documentation)
10. [Security](#security)
11. [Testing](#testing)

---

## 📖 Overview

Volt Guard is a comprehensive smart energy management solution that combines IoT sensors, cloud infrastructure, and artificial intelligence to provide real-time energy monitoring, predictive analytics, and automated anomaly detection. The system collects energy consumption data from IoT-enabled devices (ESP32/ESP8266), processes it through AI models, and delivers actionable insights through a mobile application.

### Key Capabilities

- **Real-time Energy Monitoring**: Continuous collection and processing of energy consumption data from multiple IoT sensors
- **AI-Powered Predictions**: Machine learning models (LSTM Neural Networks and Random Forest) predict future energy consumption patterns
- **Anomaly Detection**: Automatic identification of unusual energy consumption patterns using Isolation Forest algorithms
- **Fault Detection**: Early detection of potential appliance malfunctions based on power consumption signatures
- **Mobile Dashboard**: Cross-platform mobile application (iOS/Android) for real-time monitoring and alerts
- **RESTful API**: Scalable Python backend with FastAPI for data management and ML model inference

---

## 🤖 Model Training

**IMPORTANT: Before using prediction and anomaly detection features, you must train the ML models first.**

### Prerequisites for Training

- MongoDB database with at least 48 hours of energy readings and occupancy telemetry data
- Python 3.9+ with required packages installed
- Minimum 1000+ clean data records for effective model training

### Training the Models

#### Step 1: Navigate to Backend Directory

```bash
cd backend
```

#### Step 2: Activate Virtual Environment

```bash
# Windows
venv\Scripts\activate

# Linux/Mac
source venv/bin/activate
```

#### Step 3: Run Training Script

```bash
python train_ml_models.py
```

This script will:
1. **Extract Data**: Pull energy readings and occupancy telemetry from MongoDB (last 48 hours)
2. **Clean Data**: Remove garbage values (device not connected, sensors not connected)
3. **Feature Engineering**: Create time-based features, rolling statistics, and aggregated features
4. **Train Models**:
   - **Anomaly Detection Model** (Isolation Forest) - Learns normal patterns
   - **Prediction Model** (Random Forest) - Fast energy predictions
   - **LSTM Model** - Advanced time-series predictions

#### Step 4: Verify Training

After training completes, verify model files were created:

```bash
# Check models directory
ls models/
# Should contain:
# - anomaly_model.pkl
# - prediction_model.pkl
# - lstm_model.h5
# - lstm_scalers.pkl
```

#### Training Output

The training script will display:
- Number of records processed
- Garbage values removed
- Model training progress
- Model performance metrics (MAE, RMSE, R² Score)
- Saved model file paths

**Example Output:**
```
Training Complete!
✅ Anomaly Detection Model: Trained (32 features)
✅ Random Forest Model: MAE: 0.0011W, R²: 0.9999
✅ LSTM Model: MAE: 0.1589W, R²: 0.5562
```

#### Retraining Models

Models should be retrained periodically (weekly/monthly) as more data becomes available:
- Better accuracy with more historical data
- Adaptation to changing usage patterns
- Improved anomaly detection thresholds

---

## 🌟 Features

### Real-time Monitoring
- Live energy consumption tracking from IoT sensors (ESP32/ESP8266)
- Current, voltage, and power measurements
- Occupancy detection via PIR and RCWL sensors
- Environmental monitoring (temperature, humidity)

### AI-Powered Predictions
- **Random Forest Model**: Fast predictions based on current conditions
- **LSTM Neural Network**: Time-series forecasting for long-term predictions
- Predictions for next 1-168 hours
- Confidence scores for each prediction

### Anomaly Detection
- **Isolation Forest Algorithm**: Unsupervised learning for anomaly detection
- Real-time detection of unusual energy patterns
- Automatic alert generation for high-severity anomalies
- Anomaly scoring and classification (High/Medium/Low)

### Fault Detection
- Appliance malfunction detection
- Power consumption signature analysis
- Predictive maintenance recommendations
- Fault severity classification

### Mobile Application
- Cross-platform Flutter app (iOS & Android)
- Real-time dashboards and charts
- Push notifications for anomalies
- Historical data visualization
- User authentication and device management

---

## 📊 Architecture

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         VOLT GUARD SYSTEM                            │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│  IoT Devices │────────▶│ MQTT Broker  │────────▶│ Backend API  │
│              │         │              │         │  (FastAPI)   │
│ • ESP32      │         │ • Mosquitto  │         │              │
│ • ESP8266    │         │ • Port 1883  │         │ Port 8000    │
│ • ACS712     │         └──────────────┘         └──────┬───────┘
│ • PIR/RCWL   │                                        │
│ • DHT22      │                                        │
└──────────────┘                                        │
                                                        ▼
                                               ┌──────────────┐
                                               │   MongoDB    │
                                               │   Database   │
                                               │              │
                                               │ Collections: │
                                               │ • energy_    │
                                               │   readings   │
                                               │ • occupancy_ │
                                               │   telemetry  │
                                               │ • devices    │
                                               │ • predictions│
                                               │ • anomalies  │
                                               │ • faults     │
                                               └──────┬───────┘
                                                      │
                                                      ▼
┌──────────────┐         ┌──────────────┐    ┌──────────────┐
│ Mobile App   │────────▶│   REST API   │◀───│  ML Models   │
│  (Flutter)   │         │  Endpoints   │    │              │
│              │         │              │    │ • Isolation  │
│ • iOS        │         │ • /prediction│    │   Forest     │
│ • Android    │         │ • /anomalies │    │ • Random     │
│              │         │ • /energy    │    │   Forest     │
│ Features:    │         │ • /devices   │    │ • LSTM       │
│ • Dashboard  │         │ • /zones     │    │              │
│ • Charts     │         │ • /faults    │    │ Models/      │
│ • Alerts     │         └──────────────┘    │ Directory    │
└──────────────┘                             └──────────────┘
```

### Data Flow

```
1. IoT Device → Collects sensor data (current, voltage, temperature, occupancy)
2. MQTT Broker → Receives and routes telemetry messages
3. Backend API → Processes and validates incoming data
4. MongoDB → Stores raw and processed data
5. ML Models → Analyze patterns and generate predictions/detections
6. REST API → Serves processed data and ML insights
7. Mobile App → Displays real-time dashboards and alerts
```

### Component Interaction

- **IoT Layer**: ESP32/ESP8266 devices with sensors publish data via MQTT
- **Backend Layer**: FastAPI application handles data ingestion, processing, and ML inference
- **Data Layer**: MongoDB stores time-series data and ML model metadata
- **ML Layer**: Trained models (LSTM, Random Forest, Isolation Forest) for predictions and anomaly detection
- **Presentation Layer**: Flutter mobile application for user interaction

---

## 🔧 Technology Stack

### Frontend
- **Framework**: Flutter 3.0+
- **Language**: Dart
- **State Management**: Provider
- **Charts & Visualization**: FL Chart
- **HTTP Client**: http package
- **Local Storage**: Shared Preferences

### Backend
- **Framework**: FastAPI
- **Language**: Python 3.9+
- **Database**: MongoDB
- **IoT Protocol**: MQTT (paho-mqtt)
- **ML/AI Libraries**:
  - TensorFlow (LSTM Neural Networks)
  - scikit-learn (Random Forest, Isolation Forest)
  - pandas (Data processing)
  - numpy (Numerical computations)
- **Authentication**: JWT (JSON Web Tokens)
- **API Documentation**: Swagger UI / ReDoc

### Infrastructure
- **Database**: MongoDB Atlas or Local MongoDB
- **Message Broker**: MQTT Broker (Mosquitto)
- **Cache** (Optional): Redis
- **Task Queue** (Optional): Celery

---

## 📦 Dependencies

### Backend Dependencies

**Core Framework:**
```
fastapi>=0.104.0          # Modern, fast web framework
uvicorn>=0.24.0           # ASGI server
pydantic>=2.0.0           # Data validation
```

**Database:**
```
pymongo>=4.6.0            # MongoDB driver
```

**Machine Learning:**
```
tensorflow>=2.14.0        # Deep learning framework for LSTM
scikit-learn>=1.3.0       # ML algorithms (Random Forest, Isolation Forest)
pandas>=2.1.0             # Data manipulation and analysis
numpy>=1.24.0             # Numerical computing
```

**Authentication & Security:**
```
python-jose[cryptography] # JWT token handling
passlib[bcrypt]>=1.7.4    # Password hashing
bcrypt>=4.1.0             # Cryptographic library
```

**Utilities:**
```
python-dotenv>=1.0.0      # Environment variable management
```

**Complete requirements.txt:**
```
fastapi
uvicorn
pymongo
python-dotenv
passlib[bcrypt]
bcrypt
python-jose[cryptography]
pandas
numpy
scikit-learn
tensorflow
pydantic
```

### Frontend Dependencies

**Core Framework:**
```yaml
flutter:
  sdk: flutter
```

**State Management:**
```yaml
provider: ^6.0.5          # State management solution
```

**HTTP & Networking:**
```yaml
http: ^1.1.0              # HTTP client for API calls
```

**Data Visualization:**
```yaml
fl_chart: ^0.63.0         # Beautiful charts and graphs
```

**Local Storage:**
```yaml
shared_preferences: ^2.2.0 # Key-value storage
```

**UI Components:**
```yaml
cupertino_icons: ^1.0.2   # iOS-style icons
```

**Development Tools:**
```yaml
flutter_lints: ^2.0.0     # Linting rules
flutter_launcher_icons: ^0.13.1
flutter_native_splash: ^2.4.1
```

### System Dependencies

**Required Software:**
- Python 3.9 or higher
- Node.js (for Flutter tooling)
- MongoDB 5.0+ (local or Atlas cloud)
- MQTT Broker (Mosquitto recommended)

**Optional Software:**
- Redis (for caching)
- Docker (for containerization)
- Git (for version control)

---

## 🚀 Getting Started

### Prerequisites Installation

#### 1. Python Setup
```bash
# Download Python 3.9+ from python.org
# Verify installation
python --version
```

#### 2. MongoDB Setup
```bash
# Option 1: Local MongoDB
# Download from mongodb.com
# Start MongoDB service
mongod

# Option 2: MongoDB Atlas (Cloud)
# Create free cluster at cloud.mongodb.com
# Get connection string
```

#### 3. Flutter Setup
```bash
# Download Flutter SDK from flutter.dev
# Add to PATH
# Verify installation
flutter doctor
```

#### 4. MQTT Broker Setup
```bash
# Install Mosquitto
# Windows: Download from mosquitto.org
# Linux: sudo apt-get install mosquitto
# Mac: brew install mosquitto

# Start broker
mosquitto -v
```

### Backend Setup

#### Step 1: Clone Repository
```bash
git clone <repository-url>
cd Volt-Guard/backend
```

#### Step 2: Create Virtual Environment
```bash
python -m venv venv

# Windows
venv\Scripts\activate

# Linux/Mac
source venv/bin/activate
```

#### Step 3: Install Dependencies
```bash
pip install -r requirements.txt
```

#### Step 4: Configure Environment
```bash
# Create .env file
cp .env.example .env

# Edit .env with your configuration:
MONGO_URI=mongodb://localhost:27017
MONGODB_DB_NAME=volt_guard
SECRET_KEY=your-secret-key-here
```

#### Step 5: Train ML Models (CRITICAL)
```bash
# Make sure you have at least 48 hours of data in MongoDB
python train_ml_models.py
```

#### Step 6: Start Backend Server
```bash
# Development mode (with auto-reload)
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Production mode
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

The API will be available at: `http://localhost:8000`

### Frontend Setup

#### Step 1: Navigate to Frontend
```bash
cd ../frontend
```

#### Step 2: Install Dependencies
```bash
flutter pub get
```

#### Step 3: Configure API Endpoint
```bash
# Edit lib/services/api_config.dart
# Set BASE_URL to your backend API URL
```

#### Step 4: Run Application
```bash
# For Android
flutter run

# For iOS (Mac only)
flutter run -d ios

# For specific device
flutter devices
flutter run -d <device-id>
```

---

## 📁 Project Structure

```
Volt-Guard/
│
├── README.md                    # This file
│
├── backend/                     # Python Backend API
│   ├── app/
│   │   ├── main.py             # FastAPI application entry point
│   │   ├── models/             # Pydantic data models
│   │   │   ├── device_model.py
│   │   │   ├── energy_model.py
│   │   │   ├── anomaly_model.py
│   │   │   ├── prediction_model.py
│   │   │   └── analytics_model.py
│   │   ├── services/           # Business logic & ML services
│   │   │   ├── data_extraction.py
│   │   │   ├── data_cleaning.py
│   │   │   ├── feature_engineering.py
│   │   │   ├── ml_service.py
│   │   │   └── lstm_service.py
│   │   └── utils/              # Utility functions
│   │       ├── jwt_handler.py
│   │       └── security.py
│   ├── routes/                 # API route handlers
│   │   ├── auth_routes.py      # Authentication endpoints
│   │   ├── devices.py          # Device management
│   │   ├── energy.py           # Energy data endpoints
│   │   ├── prediction.py       # ML prediction endpoints
│   │   ├── anomalies.py        # Anomaly detection endpoints
│   │   ├── faults.py           # Fault detection endpoints
│   │   ├── analytics.py        # Analytics endpoints
│   │   ├── zones.py            # Zone management
│   │   └── user_routes.py      # User management
│   ├── database.py             # MongoDB connection
│   ├── requirements.txt        # Python dependencies
│   ├── train_ml_models.py      # ML model training script
│   ├── models/                 # Trained ML models (generated)
│   │   ├── anomaly_model.pkl
│   │   ├── prediction_model.pkl
│   │   ├── lstm_model.h5
│   │   └── lstm_scalers.pkl
│   └── clean_dataset.csv       # Cleaned training data (generated)
│
├── frontend/                    # Flutter Mobile Application
│   ├── lib/
│   │   ├── main.dart           # App entry point
│   │   ├── pages/              # UI pages/screens
│   │   │   ├── main_page.dart
│   │   │   ├── devices_page.dart
│   │   │   ├── analytics_page.dart
│   │   │   └── zones_page.dart
│   │   ├── services/           # API services
│   │   │   ├── api_config.dart
│   │   │   ├── auth_service.dart
│   │   │   ├── device_service.dart
│   │   │   ├── analytics_service.dart
│   │   │   └── zones_service.dart
│   │   ├── models/             # Data models
│   │   │   ├── energy_reading.dart
│   │   │   └── sensor_reading.dart
│   │   └── widgets/            # Reusable widgets
│   ├── assets/                 # Images, fonts, resources
│   ├── android/                # Android configuration
│   ├── ios/                    # iOS configuration
│   ├── pubspec.yaml            # Flutter dependencies
│   └── test/                   # Frontend tests
│
└── voltguard-api/              # Legacy Flask API (optional)
    └── app.py
```

---

## 📖 API Documentation

### Interactive Documentation

Once the backend is running, access interactive API documentation:

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Key API Endpoints

#### Authentication
- `POST /auth/register` - Register new user
- `POST /auth/login` - User login (get JWT token)

#### Energy Data
- `POST /energy` - Store energy readings
- `GET /energy/latest` - Get latest energy readings

#### Predictions
- `GET /prediction/predict` - Predict future energy consumption
- `GET /prediction/compare` - Compare Random Forest vs LSTM predictions

#### Anomaly Detection
- `GET /anomalies/detect` - Detect anomalies in recent data
- `GET /anomalies/stats` - Get anomaly statistics
- `GET /anomalies/active` - Get active high-severity anomalies

#### Devices & Zones
- `GET /devices` - List all devices
- `GET /zones` - List all zones/locations
- `POST /zones/{location}/devices` - Add device to zone

#### Analytics
- `GET /analytics/latest` - Get latest sensor readings
- `GET /analytics/stats` - Get occupancy statistics

### API Authentication

Most endpoints require JWT authentication. Include token in headers:
```
Authorization: Bearer <your-jwt-token>
```

---

## 🔐 Security

- **JWT Authentication**: Secure token-based authentication for API access
- **Password Hashing**: Bcrypt password hashing with salt
- **CORS Protection**: Configurable Cross-Origin Resource Sharing
- **Input Validation**: Pydantic models for request validation
- **Environment Variables**: Sensitive data stored in .env files (not committed)
- **HTTPS Support**: Production deployments should use HTTPS
- **API Rate Limiting**: (Recommended for production)

---

## 🧪 Testing

### Backend Tests

```bash
cd backend
pytest                          # Run all tests
pytest --cov=app tests/        # Run with coverage
pytest tests/test_main.py      # Run specific test file
```

### Frontend Tests

```bash
cd frontend
flutter test                    # Run all tests
flutter test test/widget_test.dart  # Run specific test
```

### Manual Testing

1. **Test API Endpoints**: Use Swagger UI at `/docs`
2. **Test Mobile App**: Run on emulator or physical device
3. **Test ML Models**: Use `/prediction/predict` and `/anomalies/detect` endpoints

---

## 📊 ML Models Overview

### 1. Anomaly Detection (Isolation Forest)
- **Type**: Unsupervised Learning
- **Purpose**: Detect unusual energy consumption patterns
- **Features**: 32+ engineered features
- **Output**: Anomaly score (0-1), severity classification
- **Training**: Automatic with contamination=0.1

### 2. Energy Prediction (Random Forest)
- **Type**: Supervised Learning (Regression)
- **Purpose**: Predict energy consumption based on current conditions
- **Features**: 32+ features (time, occupancy, historical patterns)
- **Output**: Predicted power in Watts
- **Performance**: MAE ~0.001W, R² ~0.9999

### 3. Time-Series Prediction (LSTM)
- **Type**: Deep Learning (Recurrent Neural Network)
- **Purpose**: Long-term energy forecasting using sequences
- **Architecture**: 2 LSTM layers (50 units each) + Dropout + Dense
- **Sequence Length**: 24-48 time steps (adaptive)
- **Features**: 7 time-series features
- **Output**: Multi-step ahead predictions
- **Performance**: MAE ~0.16W, R² ~0.56 (improves with more data)

---

## 🔄 Data Pipeline

### 1. Data Collection
- IoT devices send telemetry via MQTT
- Backend receives and validates data
- Data stored in MongoDB

### 2. Data Cleaning
- Remove garbage values (device not connected: current_a=0)
- Remove invalid sensor readings (temperature=0, humidity=0)
- Handle missing values
- Remove outliers using IQR method

### 3. Feature Engineering
- Time features: hour, day_of_week, is_weekend
- Cyclical encoding: hour_sin, hour_cos, day_sin, day_cos
- Rolling statistics: 1-hour mean, std
- Lag features: value_1_step_ago, value_2_steps_ago
- Aggregated features: daily_mean, daily_max, daily_min

### 4. Model Inference
- Anomaly detection on new data
- Energy predictions for future time periods
- Results stored and served via API

---

## 🚦 Deployment

### Development

```bash
# Backend
uvicorn app.main:app --reload

# Frontend
flutter run
```

### Production

```bash
# Backend (with multiple workers)
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4

# Frontend
flutter build apk          # Android
flutter build ios          # iOS
```

### Docker (Recommended)

```bash
# Build and run backend
docker build -t voltguard-backend .
docker run -p 8000:8000 voltguard-backend
```

---

## 📝 License

This project is part of the Volt Guard Smart Energy Management System.

---

## 👥 Team

Smart Energy Management System Development Team

---

## 📧 Support

For questions, issues, or contributions:
- Open an issue in the repository
- Check documentation in `/docs` folder
- Review API docs at `/docs` endpoint when server is running

---

**Built with ❤️ for a sustainable energy future**

---

## 📚 Additional Resources

- [Backend README](backend/README.md) - Detailed backend documentation
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Flutter Documentation](https://flutter.dev/docs)
- [TensorFlow Guide](https://www.tensorflow.org/guide)
- [MongoDB Documentation](https://docs.mongodb.com/)
