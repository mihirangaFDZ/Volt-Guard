# Volt Guard - Backend (Python)

This is the Python backend API for the Volt Guard Smart Energy Management System.

## About

Volt Guard is an AI-based system that:
- Analyzes energy consumption data from IoT devices
- Predicts future energy usage using machine learning
- Detects abnormal consumption patterns
- Identifies faults in appliances

## Technology Stack

- **Framework**: FastAPI
- **Database**: MongoDB
- **Cache**: Redis
- **IoT Protocol**: MQTT
- **AI/ML**: TensorFlow, scikit-learn
- **Task Queue**: Celery

## Features

- RESTful API endpoints for energy data
- Real-time IoT device data collection via MQTT
- AI-powered energy usage prediction
- Anomaly detection algorithms
- Device fault detection
- User authentication and authorization
- Data analytics and reporting

## Getting Started

### Prerequisites

- Python 3.9+
- MongoDB
- Redis (optional, for caching)
- MQTT Broker (e.g., Mosquitto)

### Installation

1. Create a virtual environment:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Set up environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. Run the application:
```bash
# Development mode
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Production mode
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

### API Documentation

Once running, access the interactive API documentation:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Project Structure

```
backend/
├── app/
│   ├── main.py           # FastAPI application entry point
│   ├── api/              # API route handlers
│   │   ├── energy.py     # Energy data endpoints
│   │   ├── devices.py    # Device management endpoints
│   │   ├── predictions.py # ML prediction endpoints
│   │   └── anomalies.py  # Anomaly detection endpoints
│   ├── models/           # Database models
│   │   ├── device.py
│   │   ├── energy.py
│   │   └── user.py
│   ├── services/         # Business logic
│   │   ├── iot_service.py      # IoT device communication
│   │   ├── ml_service.py       # Machine learning models
│   │   ├── prediction_service.py # Energy prediction
│   │   └── anomaly_service.py  # Anomaly detection
│   └── utils/            # Utility functions
│       ├── database.py
│       ├── mqtt_client.py
│       └── auth.py
├── tests/                # Unit and integration tests
├── config/               # Configuration files
├── requirements.txt      # Python dependencies
└── .env.example         # Environment variables template
```

## API Endpoints

### Core Endpoints
- `GET /` - API welcome message
- `GET /health` - Health check

### Energy Data (planned)
- `GET /api/v1/energy` - Get energy consumption data
- `POST /api/v1/energy` - Record energy data
- `GET /api/v1/energy/stats` - Get energy statistics

### Devices (planned)
- `GET /api/v1/devices` - List all devices
- `POST /api/v1/devices` - Register a new device
- `GET /api/v1/devices/{id}` - Get device details
- `PUT /api/v1/devices/{id}` - Update device
- `DELETE /api/v1/devices/{id}` - Remove device

### Predictions (planned)
- `GET /api/v1/predictions` - Get energy predictions
- `POST /api/v1/predictions/generate` - Generate new predictions

### Anomalies (planned)
- `GET /api/v1/anomalies` - Get detected anomalies
- `GET /api/v1/anomalies/{id}` - Get anomaly details

## IoT Integration

The system connects to IoT devices via MQTT protocol:

```python
# Topic structure
voltguard/devices/{device_id}/energy
voltguard/devices/{device_id}/status
voltguard/alerts/{device_id}
```

## Machine Learning

### Energy Prediction
- Uses time series forecasting (LSTM, Prophet)
- Predicts energy usage for next 24-48 hours
- Factors: historical data, weather, time patterns

### Anomaly Detection
- Identifies unusual energy consumption patterns
- Uses isolation forests and autoencoders
- Real-time alerting for anomalies

### Fault Detection
- Detects appliance malfunctions
- Analyzes power consumption signatures
- Provides maintenance recommendations

## Testing

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=app tests/

# Run specific test file
pytest tests/test_energy.py
```

## Development

### Code Style
- Follow PEP 8 guidelines
- Use Black for code formatting
- Use Flake8 for linting

```bash
# Format code
black app/

# Lint code
flake8 app/
```

## Deployment

### Docker (Recommended)
```bash
docker build -t voltguard-backend .
docker run -p 8000:8000 voltguard-backend
```

### Production Considerations
- Use environment-specific .env files
- Set up proper MongoDB indexes
- Configure CORS appropriately
- Enable rate limiting
- Set up monitoring and logging
- Use HTTPS in production

## Contributing

1. Create a feature branch
2. Make your changes
3. Write/update tests
4. Ensure all tests pass
5. Submit a pull request

## License

This project is part of the Volt Guard Smart Energy Management System.
