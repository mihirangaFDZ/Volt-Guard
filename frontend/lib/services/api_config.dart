/// API Configuration for Volt Guard
/// 
/// This file contains the configuration for connecting to the backend API.
/// Update the baseUrl for different environments (development, staging, production).

class ApiConfig {
  // Base URL for the API
  // Change this to your backend server URL
  static const String baseUrl = 'https://voltguard-backend-b8fwhaduh0hpd8ht.centralindia-01.azurewebsites.net';
  
  // API version prefix
  static const String apiVersion = '/api/v1';
  
  // Full API base URL
  static String get apiBaseUrl => '$baseUrl$apiVersion';
  
  // API Endpoints
  static const String energyEndpoint = '/energy';
  static const String devicesEndpoint = '/devices';
  static const String predictionsEndpoint = '/predictions';
  static const String anomaliesEndpoint = '/anomalies';
  static const String userEndpoint = '/users';
  static const String analyticsEndpoint = '/analytics';
  static const String authEndpoint = '/auth/login'; 
  static const String signupEndpoint = '/users/signup';
  static const String faultsEndpoint = '/faults';

  
  // Request timeout duration
  static const Duration requestTimeout = Duration(seconds: 30);
  
  // Environment-specific configurations
  static bool get isDevelopment => _environment == Environment.development;
  static bool get isProduction => _environment == Environment.production;
  
  static Environment _environment = Environment.development;
  
  static void setEnvironment(Environment env) {
    _environment = env;
  }
}

/// Application environment
enum Environment {
  development,
  staging,
  production,
}
