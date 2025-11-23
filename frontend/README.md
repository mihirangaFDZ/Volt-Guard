# Volt Guard - Frontend (Flutter)

This is the mobile application frontend for the Volt Guard Smart Energy Management System.

## About

Volt Guard is an AI-based system that:
- Analyzes energy consumption data from IoT devices
- Predicts future energy usage
- Detects abnormal consumption patterns
- Identifies faults in appliances

## Features

- Real-time energy monitoring
- Energy consumption analytics
- Predictive energy usage forecasting
- Anomaly detection alerts
- Appliance fault detection
- User-friendly dashboard

## Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Dart SDK
- Android Studio / Xcode (for mobile development)
- VS Code or Android Studio IDE

### Installation

1. Install Flutter dependencies:
```bash
flutter pub get
```

2. Run the application:
```bash
# For development
flutter run

# For specific platform
flutter run -d android
flutter run -d ios
```

### Building

```bash
# Build APK for Android
flutter build apk

# Build iOS
flutter build ios
```

## Project Structure

```
frontend/
├── lib/              # Main application code
│   ├── main.dart     # Application entry point
│   ├── screens/      # UI screens
│   ├── widgets/      # Reusable widgets
│   ├── models/       # Data models
│   ├── services/     # API services
│   └── utils/        # Utility functions
├── assets/           # Images, fonts, and other assets
├── test/             # Unit and widget tests
└── android/          # Android-specific code
└── ios/              # iOS-specific code
```

## Backend Integration

The mobile app connects to the Python backend API for:
- Energy data retrieval
- AI predictions
- Anomaly detection results
- Device management

Backend API URL configuration can be found in `lib/services/api_config.dart`.

## Testing

```bash
# Run all tests
flutter test

# Run specific test
flutter test test/widget_test.dart
```

## Contributing

1. Create a feature branch
2. Make your changes
3. Test thoroughly
4. Submit a pull request

## License

This project is part of the Volt Guard Smart Energy Management System.
