# Volt Guard
## Smart Energy Management System Using IoT and Data Analytics

Volt Guard is an AI-powered energy management system that analyzes energy consumption data from IoT devices, predicts future energy usage, and detects abnormal consumption patterns or faults in appliances.

## 🌟 Features

- **Real-time Monitoring**: Track energy consumption from IoT-enabled devices
- **AI-Powered Predictions**: Machine learning models predict future energy usage
- **Anomaly Detection**: Automatically detect unusual consumption patterns
- **Fault Detection**: Identify potential appliance malfunctions before they fail
- **Mobile Application**: User-friendly Flutter-based mobile app for iOS and Android
- **RESTful API**: Python backend with FastAPI for robust data management
- **Data Analytics**: Comprehensive insights and visualizations

## 📁 Project Structure

```
Volt-Guard/
├── frontend/          # Flutter mobile application
│   ├── lib/          # Dart source code
│   ├── assets/       # Images, fonts, and resources
│   ├── android/      # Android-specific configuration
│   ├── ios/          # iOS-specific configuration
│   └── test/         # Frontend tests
│
├── backend/          # Python API server
│   ├── app/          # Application code
│   │   ├── api/      # API endpoints
│   │   ├── models/   # Database models
│   │   ├── services/ # Business logic
│   │   └── utils/    # Utility functions
│   ├── tests/        # Backend tests
│   └── config/       # Configuration files
│
└── README.md         # This file
```

## 🚀 Getting Started

### Prerequisites

**Frontend:**
- Flutter SDK (>=3.0.0)
- Dart SDK
- Android Studio or Xcode

**Backend:**
- Python 3.9+
- MongoDB
- Redis (optional)
- MQTT Broker (e.g., Mosquitto)

### Quick Start

#### Frontend Setup

```bash
cd frontend
flutter pub get
flutter run
```

For detailed frontend instructions, see [frontend/README.md](frontend/README.md)

#### Backend Setup

```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your configuration
uvicorn app.main:app --reload
```

For detailed backend instructions, see [backend/README.md](backend/README.md)

## 🔧 Technology Stack

### Frontend
- **Framework**: Flutter
- **Language**: Dart
- **State Management**: Provider
- **Charts**: FL Chart
- **HTTP Client**: http package

### Backend
- **Framework**: FastAPI
- **Language**: Python
- **Database**: MongoDB
- **Cache**: Redis
- **IoT Protocol**: MQTT
- **ML/AI**: TensorFlow, scikit-learn
- **Task Queue**: Celery

## 📊 Architecture

```
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│  IoT Devices    │─────▶│  MQTT Broker    │─────▶│  Backend API    │
│  (Sensors)      │      │                 │      │  (Python)       │
└─────────────────┘      └─────────────────┘      └────────┬────────┘
                                                            │
                                                            ▼
                                                   ┌─────────────────┐
                                                   │    Database     │
                                                   │   (MongoDB)     │
                                                   └─────────────────┘
                                                            │
                                                            ▼
                                                   ┌─────────────────┐
                                                   │   ML Models     │
                                                   │  (Predictions)  │
                                                   └─────────────────┘
                                                            │
                                                            ▼
                                                   ┌─────────────────┐
                                                   │  Mobile App     │
                                                   │   (Flutter)     │
                                                   └─────────────────┘
```

## 🔐 Security

- JWT-based authentication
- Secure API endpoints
- Encrypted data transmission
- Environment-based configuration
- Input validation and sanitization

## 🧪 Testing

### Frontend Tests
```bash
cd frontend
flutter test
```

### Backend Tests
```bash
cd backend
pytest
```

## 📖 API Documentation

Once the backend is running, access the interactive API documentation:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is part of the Volt Guard Smart Energy Management System.

## 👥 Team

Smart Energy Management System Development Team

## 📧 Contact

For questions and support, please open an issue in the repository.

---

**Built with ❤️ for a sustainable energy future**
