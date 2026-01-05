# Volt Guard
## Smart Energy Management System Using IoT and AI-Based Data Analytics

Volt Guard is an advanced AI-powered energy management system that analyzes energy consumption data from IoT devices, predicts future energy usage using machine learning models, detects abnormal consumption patterns, and identifies potential faults in appliances in real-time.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Model Training](#model-training)
4. [Features](#features)
5. [Architecture](#architecture)
6. [Technology Stack](#technology-stack)
7. [Dependencies](#dependencies)
8. [Getting Started](#getting-started)
9. [IoT Hardware Setup](#iot-hardware-setup)
10. [Project Structure](#project-structure)
11. [API Documentation](#api-documentation)
12. [Security](#security)
13. [Testing](#testing)
14. [Deployment](#deployment)

---

## 📖 Overview

Volt Guard is a comprehensive smart energy management solution that combines IoT sensors, cloud infrastructure, and artificial intelligence to provide real-time energy monitoring, predictive analytics, and automated anomaly detection. The system collects energy consumption data from IoT-enabled devices (ESP32/ESP8266), processes it through AI models, and delivers actionable insights through a mobile application.

### Project Purpose

Volt Guard addresses the growing need for intelligent energy management in residential and commercial settings. By leveraging IoT sensors and machine learning, the system enables users to:

- Monitor energy consumption in real-time across multiple locations/zones
- Predict future energy usage patterns to optimize consumption
- Detect anomalies and potential faults before they become critical issues
- Make data-driven decisions to reduce energy costs and improve efficiency

### Key Capabilities

- **Real-time Energy Monitoring**: Continuous collection and processing of energy consumption data from multiple IoT sensors (current, voltage, power, energy)
- **AI-Powered Predictions**: Machine learning models (LSTM Neural Networks and Random Forest) predict future energy consumption patterns with high accuracy
- **Anomaly Detection**: Automatic identification of unusual energy consumption patterns using Isolation Forest algorithms, enabling early warning of potential issues
- **Fault Detection**: Early detection of potential appliance malfunctions based on power consumption signatures and pattern analysis
- **Occupancy Analytics**: Integration of occupancy sensors (PIR, RCWL) and environmental sensors (DHT22) for comprehensive space monitoring
- **Mobile Dashboard**: Cross-platform mobile application (iOS/Android) for real-time monitoring, historical data visualization, and alerts
- **RESTful API**: Scalable Python backend with FastAPI for data management, ML model inference, and secure API access
- **Zone Management**: Organize and monitor multiple locations/zones with device grouping and location-based analytics
- **User Authentication**: Secure JWT-based authentication system for multi-user access control

### System Components

1. **IoT Hardware**: ESP32/ESP8266 microcontrollers with various sensors
2. **Backend API**: FastAPI-based REST API for data processing and ML inference
3. **Legacy API**: Flask-based API for telemetry ingestion (alternative to MQTT)
4. **Database**: MongoDB for time-series data storage
5. **ML Models**: Three trained models for predictions and anomaly detection
6. **Mobile App**: Flutter application for iOS and Android platforms

---

## ⚡ Quick Start

### Prerequisites Checklist

- [ ] Python 3.9+ installed
- [ ] Flutter SDK 3.0+ installed
- [ ] MongoDB installed (local or Atlas account)
- [ ] Git installed
- [ ] Code editor (VS Code recommended)

### 5-Minute Setup

**1. Clone the Repository**
```bash
git clone <repository-url>
cd Volt-Guard
```

**2. Setup Backend**
```bash
cd backend
python -m venv venv
venv\Scripts\activate  # Windows
# or
source venv/bin/activate  # Linux/Mac

pip install -r requirements.txt

# Create .env file with MongoDB connection
# MONGO_URI=mongodb://localhost:27017
# MONGODB_DB_NAME=volt_guard
# SECRET_KEY=your-secret-key

uvicorn app.main:app --reload
```

**3. Setup Frontend**
```bash
cd ../frontend
flutter pub get
flutter run
```

**4. Access the System**
- Backend API: http://localhost:8000
- API Docs: http://localhost:8000/docs
- Mobile App: Running on your device/emulator

**Note:** For ML features to work, you need to train the models first (see [Model Training](#model-training) section).

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

### System Architecture Overview

Volt Guard follows a layered architecture pattern with clear separation of concerns:

1. **IoT Layer**: Hardware devices collecting sensor data
2. **Communication Layer**: MQTT broker for real-time data transmission
3. **Backend Layer**: FastAPI REST API for data processing and ML inference
4. **Data Layer**: MongoDB for persistent storage
5. **ML Layer**: Trained machine learning models for predictions and anomaly detection
6. **Presentation Layer**: Flutter mobile application for user interaction

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          VOLT GUARD SYSTEM ARCHITECTURE                      │
└─────────────────────────────────────────────────────────────────────────────┘

                                    ┌──────────────┐
                                    │   Users      │
                                    │  (Mobile)    │
                                    └──────┬───────┘
                                           │ HTTPS/REST API
                                           │
                    ┌──────────────────────┴──────────────────────┐
                    │                                            │
                    ▼                                            ▼
        ┌──────────────────────┐              ┌──────────────────────┐
        │   Mobile App         │              │   Legacy API          │
        │   (Flutter)          │              │   (Flask)             │
        │                      │              │                       │
        │ • iOS                │              │ • Telemetry Endpoint  │
        │ • Android            │              │ • Health Check        │
        │                      │              │ • Port: Variable      │
        │ Features:            │              └──────────┬───────────┘
        │ • Dashboard          │                         │
        │ • Real-time Charts   │                         │
        │ • Anomaly Alerts     │                         │
        │ • Device Management  │                         │
        │ • Zone Management    │                         │
        └──────────┬───────────┘                         │
                   │                                      │
                   │ REST API                            │ HTTP POST
                   │ (JWT Auth)                          │ (API Key Auth)
                   │                                      │
                   └──────────────┬───────────────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────────┐
                    │    Backend API (FastAPI)   │
                    │                            │
                    │ • Port: 8000               │
                    │ • Authentication: JWT      │
                    │ • API Docs: /docs           │
                    │                            │
                    │ Routes:                     │
                    │ • /auth/*                   │
                    │ • /energy/*                 │
                    │ • /devices/*                │
                    │ • /zones/*                 │
                    │ • /prediction/*             │
                    │ • /anomalies/*              │
                    │ • /faults/*                 │
                    │ • /analytics/*              │
                    │ • /users/*                  │
                    └────────────┬────────────────┘
                                 │
                ┌────────────────┼────────────────┐
                │                │                │
                ▼                ▼                ▼
    ┌──────────────────┐  ┌──────────────┐  ┌──────────────┐
    │   MongoDB        │  │  ML Models   │  │  MQTT        │
    │   Database       │  │  Directory   │  │  Subscriber  │
    │                  │  │              │  │              │
    │ Collections:     │  │ • anomaly_   │  │ (Optional)   │
    │ • energy_        │  │   model.pkl  │  │              │
    │   readings       │  │ • prediction_│  │              │
    │ • occupancy_     │  │   model.pkl  │  │              │
    │   telemetry      │  │ • lstm_model │  │              │
    │ • devices        │  │   .h5        │  │              │
    │ • predictions    │  │ • lstm_      │  │              │
    │ • anomalies      │  │   scalers.   │  │              │
    │ • faults         │  │   pkl        │  │              │
    │ • users          │  │              │  │              │
    │ • zones          │  └──────────────┘  └──────────────┘
    └──────────────────┘                            │
                                                     │ MQTT Protocol
                                                     │ (Port 1883)
                                                     │
                                                     ▼
                                    ┌─────────────────────────┐
                                    │    MQTT Broker          │
                                    │    (Mosquitto)           │
                                    │                          │
                                    │ Topics:                  │
                                    │ • energy/telemetry       │
                                    │ • occupancy/telemetry    │
                                    └────────────┬──────────────┘
                                                 │
                                                 │ MQTT Publish
                                                 │
                    ┌────────────────────────────┴────────────────────────────┐
                    │                                                         │
                    ▼                                                         ▼
        ┌──────────────────────┐                              ┌──────────────────────┐
        │   IoT Devices        │                              │   IoT Devices        │
        │   (ESP32/ESP8266)    │                              │   (ESP32/ESP8266)    │
        │                      │                              │                      │
        │ Sensors:             │                              │ Sensors:             │
        │ • ACS712             │                              │ • PIR Sensor         │
        │   (Current Sensor)   │                              │ • RCWL Sensor        │
        │ • Voltage Divider    │                              │ • DHT22              │
        │                      │                              │   (Temp/Humidity)    │
        │ Data Collected:      │                              │                      │
        │ • Current (A)        │                              │ Data Collected:      │
        │ • Voltage (V)        │                              │ • Occupancy Status   │
        │ • Power (W)          │                              │ • Temperature (°C)   │
        │ • Energy (kWh)       │                              │ • Humidity (%)       │
        │ • Location           │                              │ • Location           │
        │ • Timestamp          │                              │ • Timestamp          │
        └──────────────────────┘                              └──────────────────────┘
```

### Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          DATA FLOW DIAGRAM                               │
└─────────────────────────────────────────────────────────────────────────┘

1. DATA COLLECTION PHASE
   ┌─────────────┐
   │ IoT Devices │ → Collect sensor readings (current, voltage, temp, etc.)
   └──────┬──────┘
          │
          │ MQTT Publish
          ▼
   ┌─────────────┐
   │MQTT Broker  │ → Routes messages to subscribers
   └──────┬──────┘
          │
          │ MQTT Subscribe (or HTTP POST for legacy)
          ▼
   ┌─────────────┐
   │Backend API  │ → Receives and validates incoming data
   └──────┬──────┘
          │
          │ Store
          ▼
   ┌─────────────┐
   │  MongoDB    │ → Persists raw sensor data
   └─────────────┘

2. DATA PROCESSING PHASE
   ┌─────────────┐
   │  MongoDB    │ → Retrieve historical data
   └──────┬──────┘
          │
          │ Query
          ▼
   ┌─────────────┐
   │Backend API  │ → Data cleaning and feature engineering
   └──────┬──────┘
          │
          │ Processed Features
          ▼
   ┌─────────────┐
   │  ML Models  │ → Generate predictions and detect anomalies
   └──────┬──────┘
          │
          │ Results
          ▼
   ┌─────────────┐
   │  MongoDB    │ → Store predictions, anomalies, and faults
   └─────────────┘

3. DATA PRESENTATION PHASE
   ┌─────────────┐
   │  MongoDB    │ → Query processed data
   └──────┬──────┘
          │
          │ REST API GET
          ▼
   ┌─────────────┐
   │Backend API  │ → Serve data via REST endpoints
   └──────┬──────┘
          │
          │ JSON Response
          ▼
   ┌─────────────┐
   │ Mobile App  │ → Display dashboards, charts, and alerts
   └─────────────┘
```

### Component Interaction Details

#### 1. IoT Layer
- **Devices**: ESP32/ESP8266 microcontrollers
- **Sensors**:
  - **ACS712**: Current sensor for measuring AC/DC current
  - **Voltage Divider**: For measuring voltage
  - **PIR Sensor**: Passive infrared motion detection
  - **RCWL Sensor**: Microwave motion detection
  - **DHT22**: Temperature and humidity sensor
- **Communication**: MQTT protocol (publish to broker) or HTTP POST (legacy API)

#### 2. Communication Layer
- **MQTT Broker**: Mosquitto (default port 1883)
- **Protocol**: MQTT 3.1.1
- **Topics**: 
  - `energy/telemetry` - Energy consumption data
  - `occupancy/telemetry` - Occupancy and environmental data
- **Alternative**: HTTP POST to legacy Flask API endpoint

#### 3. Backend Layer
- **Framework**: FastAPI (Python)
- **Authentication**: JWT tokens for secure API access
- **Features**:
  - Data validation using Pydantic models
  - Automatic API documentation (Swagger UI)
  - CORS middleware for cross-origin requests
  - Route handlers for all business logic

#### 4. Data Layer
- **Database**: MongoDB (NoSQL document database)
- **Collections**:
  - `energy_readings`: Time-series energy consumption data
  - `occupancy_telemetry`: Occupancy and environmental sensor data
  - `devices`: Registered IoT device information
  - `predictions`: ML model predictions
  - `anomalies`: Detected anomaly records
  - `faults`: Detected fault records
  - `users`: User accounts and authentication data
  - `zones`: Location/zone management data

#### 5. ML Layer
- **Models**:
  - **Isolation Forest**: Unsupervised anomaly detection
  - **Random Forest**: Fast energy consumption prediction
  - **LSTM Neural Network**: Time-series forecasting
- **Storage**: Trained models stored in `backend/models/` directory
- **Inference**: Models loaded and used for real-time predictions

#### 6. Presentation Layer
- **Framework**: Flutter (Dart)
- **Platforms**: iOS and Android
- **Features**:
  - Real-time data visualization
  - Interactive charts and graphs
  - Push notifications for anomalies
  - User authentication
  - Device and zone management

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

### Backend Dependencies (FastAPI)

The main backend API is built with FastAPI and requires the following Python packages:

**Core Framework:**
```
fastapi                 # Modern, fast web framework for building APIs
uvicorn                 # ASGI server for running FastAPI applications
pydantic                # Data validation using Python type annotations
```

**Database:**
```
pymongo                 # MongoDB driver for Python
```

**Machine Learning & Data Science:**
```
tensorflow              # Deep learning framework for LSTM neural networks
scikit-learn            # ML algorithms (Random Forest, Isolation Forest)
pandas                  # Data manipulation and analysis
numpy                   # Numerical computing library
```

**Authentication & Security:**
```
python-jose[cryptography]  # JWT token encoding/decoding
passlib[bcrypt]            # Password hashing with bcrypt
bcrypt                     # Cryptographic library for password hashing
```

**Utilities:**
```
python-dotenv            # Environment variable management from .env files
```

**Complete Backend requirements.txt:**
```txt
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

**Installation:**
```bash
cd backend
pip install -r requirements.txt
```

### Legacy API Dependencies (Flask)

The legacy Flask API in `voltguard-api/` requires:

```txt
flask                   # Lightweight web framework
pymongo                 # MongoDB driver
python-dotenv           # Environment variable management
gunicorn                # WSGI HTTP server for production
pytz                    # Timezone definitions and conversions
```

**Installation:**
```bash
cd voltguard-api
pip install -r requirements.txt
```

### Frontend Dependencies (Flutter)

The mobile application is built with Flutter and uses the following packages:

**Core Framework:**
```yaml
flutter:
  sdk: flutter           # Flutter SDK (version 3.0+)
```

**State Management:**
```yaml
provider: ^6.0.5        # State management solution using Provider pattern
```

**HTTP & Networking:**
```yaml
http: ^1.1.0            # HTTP client for making API calls to backend
```

**Data Visualization:**
```yaml
fl_chart: ^0.63.0       # Beautiful charts and graphs for data visualization
```

**Local Storage:**
```yaml
shared_preferences: ^2.2.0  # Key-value storage for persisting user preferences
```

**UI Components:**
```yaml
cupertino_icons: ^1.0.2  # iOS-style icons
```

**Development Tools:**
```yaml
flutter_lints: ^2.0.0              # Linting rules for Flutter
flutter_launcher_icons: ^0.13.1   # Generate app launcher icons
flutter_native_splash: ^2.4.1     # Generate native splash screens
```

**Complete Frontend pubspec.yaml dependencies:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.2
  http: ^1.1.0
  provider: ^6.0.5
  shared_preferences: ^2.2.0
  fl_chart: ^0.63.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0
  flutter_launcher_icons: ^0.13.1
  flutter_native_splash: ^2.4.1
```

**Installation:**
```bash
cd frontend
flutter pub get
```

### System Dependencies

**Required Software:**
- **Python 3.9+**: Required for backend API and ML model training
- **Flutter SDK 3.0+**: Required for mobile application development
- **MongoDB 5.0+**: Database (local installation or MongoDB Atlas cloud)
- **MQTT Broker**: Message broker for IoT device communication (Mosquitto recommended)
- **Git**: Version control system

**Platform-Specific Requirements:**

**For Android Development:**
- Android Studio
- Android SDK
- Java Development Kit (JDK)

**For iOS Development (macOS only):**
- Xcode 14+
- CocoaPods
- iOS SDK

**Optional Software:**
- **Redis**: For caching (optional, not currently implemented)
- **Docker**: For containerization and deployment
- **Node.js**: Required for Flutter tooling and development
- **Postman/Insomnia**: For API testing

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

## 🔌 IoT Hardware Setup

### Required Hardware Components

**Microcontrollers:**
- **ESP32** or **ESP8266** - WiFi-enabled microcontroller for IoT connectivity
- Recommended: ESP32 (more processing power and features)

**Energy Monitoring Sensors:**
- **ACS712 Current Sensor** - Measures AC/DC current (5A, 20A, or 30A variants)
- **Voltage Divider Circuit** - For measuring AC/DC voltage (using resistors)

**Occupancy & Environmental Sensors:**
- **PIR Sensor** (HC-SR501) - Passive infrared motion detection
- **RCWL-0516 Sensor** - Microwave motion detection (alternative to PIR)
- **DHT22 Sensor** - Temperature and humidity sensor

**Additional Components:**
- Resistors for voltage divider
- Jumper wires
- Breadboard or PCB
- Power supply (5V for ESP32, 3.3V for ESP8266)
- USB cable for programming

### Hardware Connections

**Energy Monitoring Setup:**
```
ESP32/ESP8266 Pin Connections:
- ACS712 VCC → 5V
- ACS712 GND → GND
- ACS712 OUT → Analog Pin (A0)
- Voltage Divider → Analog Pin (A1)
```

**Occupancy Sensor Setup:**
```
ESP32/ESP8266 Pin Connections:
- PIR VCC → 5V
- PIR GND → GND
- PIR OUT → Digital Pin (D2)
- RCWL VCC → 5V
- RCWL GND → GND
- RCWL OUT → Digital Pin (D3)
```

**Environmental Sensor Setup:**
```
ESP32/ESP8266 Pin Connections:
- DHT22 VCC → 3.3V or 5V
- DHT22 GND → GND
- DHT22 DATA → Digital Pin (D4)
```

### IoT Device Configuration

**WiFi Setup:**
- Configure WiFi SSID and password in device firmware
- Ensure device can connect to same network as MQTT broker/backend API

**MQTT Configuration:**
- MQTT Broker IP address (e.g., `192.168.1.100` or `mqtt.example.com`)
- MQTT Port (default: 1883)
- MQTT Topics:
  - Energy data: `energy/telemetry`
  - Occupancy data: `occupancy/telemetry`
- Device ID/Client ID for MQTT connection

**Alternative: HTTP POST (Legacy API):**
- If MQTT is not available, devices can POST directly to Flask API
- Endpoint: `http://your-api-url/api/v1/telemetry`
- Authentication: Include `X-API-Key` header
- Data format: JSON payload matching sensor reading models

### Data Format

**Energy Reading Format:**
```json
{
  "device_id": "ESP32_001",
  "location": "Living Room",
  "current_a": 2.5,
  "voltage": 230.0,
  "power": 575.0,
  "energy": 0.575,
  "timestamp": "2024-01-15T10:30:00Z"
}
```

**Occupancy/Environmental Reading Format:**
```json
{
  "module": "ESP32_001",
  "location": "Living Room",
  "rcwl": 1,
  "pir": 1,
  "temperature": 25.5,
  "humidity": 60.0,
  "received_at": "2024-01-15T10:30:00Z"
}
```

### Firmware Development

**Required Libraries (Arduino IDE):**
- ESP32/ESP8266 board support
- WiFi library
- MQTT library (PubSubClient) or HTTP client
- DHT sensor library (for DHT22)
- ACS712 library (for current sensor)

**Key Features to Implement:**
- WiFi connection management
- MQTT connection and reconnection logic
- Sensor reading collection
- Data formatting and transmission
- Error handling and logging
- OTA (Over-The-Air) updates (optional)

---

## 📁 Project Structure

```
Volt-Guard/
│
├── README.md                    # Project documentation (this file)
├── .gitignore                   # Git ignore rules
├── render.yaml                  # Render.com deployment configuration
│
├── backend/                     # Python Backend API (FastAPI)
│   ├── app/
│   │   ├── main.py             # FastAPI application entry point
│   │   ├── models/             # Pydantic data models
│   │   │   ├── device_model.py      # Device data models
│   │   │   ├── energy_model.py      # Energy reading models
│   │   │   ├── anomaly_model.py     # Anomaly detection models
│   │   │   ├── prediction_model.py  # Prediction models
│   │   │   ├── analytics_model.py   # Analytics sensor models
│   │   │   ├── fault_model.py       # Fault detection models
│   │   │   ├── user_model.py        # User authentication models
│   │   │   └── zone_model.py         # Zone/location models
│   │   ├── services/           # Business logic & ML services
│   │   │   └── (ML service implementations)
│   │   └── utils/              # Utility functions
│   │       ├── jwt_handler.py       # JWT token management
│   │       └── security.py          # Security utilities
│   ├── routes/                 # API route handlers
│   │   ├── auth_routes.py      # Authentication endpoints (/auth/*)
│   │   ├── devices.py          # Device management (/devices/*)
│   │   ├── energy.py           # Energy data endpoints (/energy/*)
│   │   ├── prediction.py       # ML prediction endpoints (/prediction/*)
│   │   ├── anomalies.py        # Anomaly detection (/anomalies/*)
│   │   ├── faults.py           # Fault detection (/faults/*)
│   │   ├── analytics.py        # Analytics endpoints (/analytics/*)
│   │   ├── zones.py            # Zone management (/zones/*)
│   │   └── user_routes.py      # User management (/users/*)
│   ├── database.py             # MongoDB connection and collections
│   ├── requirements.txt        # Python dependencies
│   ├── train_ml_models.py      # ML model training script (if exists)
│   ├── models/                 # Trained ML models (generated)
│   │   ├── anomaly_model.pkl        # Isolation Forest model
│   │   ├── prediction_model.pkl     # Random Forest model
│   │   ├── lstm_model.h5             # LSTM neural network
│   │   ├── lstm_best_model.h5       # Best LSTM model
│   │   └── lstm_scalers.pkl         # LSTM feature scalers
│   ├── tests/                  # Backend unit tests
│   │   └── test_main.py
│   └── venv/                   # Python virtual environment
│
├── frontend/                    # Flutter Mobile Application
│   ├── lib/
│   │   ├── main.dart           # App entry point
│   │   ├── pages/              # UI pages/screens
│   │   │   ├── main_page.dart         # Main navigation page
│   │   │   ├── dashboard_page.dart    # Energy dashboard
│   │   │   ├── devices_page.dart      # Device management
│   │   │   ├── analytics_page.dart    # Analytics and charts
│   │   │   ├── zones_page.dart        # Zone overview
│   │   │   ├── zone_details_page.dart # Zone detail view
│   │   │   ├── zone_manager_page.dart # Zone management
│   │   │   └── profile_page.dart      # User profile
│   │   ├── screens/            # Authentication screens
│   │   │   ├── welcome_screen.dart    # Welcome/onboarding
│   │   │   ├── login_screen.dart      # User login
│   │   │   └── signup_screen.dart     # User registration
│   │   ├── services/           # API services
│   │   │   ├── api_config.dart        # API configuration
│   │   │   ├── auth_service.dart      # Authentication service
│   │   │   ├── device_service.dart    # Device API calls
│   │   │   ├── energy_service.dart    # Energy data API calls
│   │   │   ├── analytics_service.dart # Analytics API calls
│   │   │   ├── zones_service.dart     # Zone API calls
│   │   │   ├── fault_detection_service.dart # Fault API calls
│   │   │   └── user_service.dart      # User API calls
│   │   └── models/             # Data models
│   │       ├── energy_reading.dart    # Energy reading model
│   │       └── sensor_reading.dart   # Sensor reading model
│   ├── assets/                 # Images, fonts, resources
│   │   ├── images/             # App icons, splash screens
│   │   └── fonts/              # Custom fonts
│   ├── android/                # Android platform configuration
│   ├── ios/                    # iOS platform configuration
│   ├── web/                    # Web platform configuration
│   ├── windows/                # Windows platform configuration
│   ├── linux/                  # Linux platform configuration
│   ├── macos/                  # macOS platform configuration
│   ├── pubspec.yaml            # Flutter dependencies and config
│   ├── generate_icon.py       # Icon generation script
│   ├── generate_splash.py     # Splash screen generation script
│   └── test/                   # Frontend unit tests
│       └── widget_test.dart
│
└── voltguard-api/              # Legacy Flask API (Alternative to MQTT)
    ├── app.py                  # Flask application entry point
    ├── requirements.txt        # Flask API dependencies
    ├── pyproject.toml          # Python project configuration
    └── runtime.txt             # Python runtime version
```

### Key Directories Explained

**Backend (`/backend`):**
- Main FastAPI application with REST endpoints
- ML model training and inference
- MongoDB database integration
- JWT authentication system

**Frontend (`/frontend`):**
- Cross-platform Flutter mobile application
- User interface for all system features
- API integration services
- Platform-specific configurations

**Legacy API (`/voltguard-api`):**
- Flask-based alternative API for telemetry ingestion
- Used when MQTT is not available
- Simple HTTP POST endpoint for IoT devices
- Deployed separately (e.g., on Render.com)

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

### Development Environment

**Backend:**
```bash
cd backend
# Activate virtual environment
venv\Scripts\activate  # Windows
# or
source venv/bin/activate  # Linux/Mac

# Run development server with auto-reload
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

**Frontend:**
```bash
cd frontend
# Install dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Run on specific platform
flutter run -d android  # Android
flutter run -d ios      # iOS (macOS only)
```

**Legacy API (Optional):**
```bash
cd voltguard-api
# Install dependencies
pip install -r requirements.txt

# Run Flask development server
python app.py
# or
flask run
```

### Production Deployment

**Backend (FastAPI):**

Using Uvicorn with multiple workers:
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

Using Gunicorn with Uvicorn workers:
```bash
gunicorn app.main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

**Frontend:**

Build production APK/IPA:
```bash
cd frontend

# Android APK
flutter build apk --release

# Android App Bundle (for Play Store)
flutter build appbundle --release

# iOS (macOS only)
flutter build ios --release
```

**Legacy API (Flask):**

Using Gunicorn:
```bash
gunicorn -w 2 -b 0.0.0.0:$PORT app:app
```

### Cloud Deployment

**Render.com Configuration:**

The project includes `render.yaml` for Render.com deployment:

```yaml
services:
  - type: web
    name: voltguard-api
    env: python
    plan: free
    buildCommand: pip install -r requirements.txt
    startCommand: gunicorn -w 2 -b 0.0.0.0:$PORT app:app
    envVars:
      - key: MONGO_URI_API
      - key: API_KEY
      - key: DB_NAME
        value: volt_guard
      - key: COLLECTION_NAME
        value: occupancy_telemetry
```

**Environment Variables Required:**

Backend (FastAPI):
```env
MONGO_URI=mongodb://localhost:27017  # or MongoDB Atlas connection string
MONGODB_DB_NAME=volt_guard
SECRET_KEY=your-secret-key-here
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
DEBUG=False
```

Legacy API (Flask):
```env
MONGO_URI_API=mongodb://localhost:27017  # or MongoDB Atlas connection string
API_KEY=your-api-key-here
DB_NAME=volt_guard
COLLECTION_NAME=occupancy_telemetry
CURRENT_COLLECTION_NAME=energy_readings
```

### Docker Deployment (Optional)

**Backend Dockerfile Example:**
```dockerfile
FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

**Build and Run:**
```bash
# Build Docker image
docker build -t voltguard-backend ./backend

# Run container
docker run -p 8000:8000 --env-file .env voltguard-backend
```

### MongoDB Setup

**Local MongoDB:**
```bash
# Install MongoDB
# Windows: Download from mongodb.com
# Linux: sudo apt-get install mongodb
# Mac: brew install mongodb-community

# Start MongoDB service
mongod
```

**MongoDB Atlas (Cloud):**
1. Create account at cloud.mongodb.com
2. Create a free cluster
3. Get connection string
4. Update `MONGO_URI` in `.env` file

### MQTT Broker Setup

**Mosquitto Installation:**
```bash
# Windows: Download from mosquitto.org
# Linux: sudo apt-get install mosquitto mosquitto-clients
# Mac: brew install mosquitto

# Start broker
mosquitto -v
```

**Configuration:**
- Default port: 1883
- No authentication required for development
- Configure authentication for production

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
