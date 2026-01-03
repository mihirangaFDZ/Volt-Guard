# Dashboard Features Documentation

## Overview

The Volt-Guard dashboard provides real-time visualization, alerts, and customizable widgets for comprehensive energy monitoring and management.

## Features Implemented

### 1. **Real-Time Visualization**

#### Energy Consumption Chart

- Live power usage monitoring with 30-second refresh intervals
- Interactive line chart showing real-time power consumption
- Color-coded visualization for better readability
- Gradient area under curve for enhanced visual appeal

#### Today's Energy Summary

- Total consumption (kWh)
- Estimated cost
- Peak hour identification
- Average power usage
- Large, easy-to-read metrics with icons

### 2. **Alert System**

#### Active Anomalies Widget

- Real-time anomaly detection and display
- Color-coded severity levels:
  - **Red**: High/Critical severity
  - **Orange**: Medium severity
  - **Yellow**: Low severity
- Device-specific anomaly information
- Quick access notification badge in app bar
- Expandable dialog for viewing all anomalies

#### Notification Service

- **Types of Notifications:**

  - Info (blue)
  - Success (green)
  - Warning (orange)
  - Error (red)
  - Anomaly alerts (red)
  - Predictions (amber)
  - Recommendations (green)

- **Notification Methods:**
  - Snackbar notifications
  - Dialog notifications
  - In-app notification center
  - Badge counters

### 3. **Customizable Widgets**

Users can customize their dashboard by toggling widgets on/off:

#### Available Widgets:

1. **Energy Summary Widget**

   - Today's total consumption
   - Cost, peak hours, average power

2. **AI Predictions Widget**

   - Tomorrow's forecasted usage
   - Percentage change from today
   - Estimated cost
   - Predicted peak hours

3. **Active Anomalies Widget**

   - Real-time alerts
   - Device-specific warnings
   - Severity indicators

4. **Real-Time Chart Widget**

   - Live power consumption graph
   - Auto-updating every 30 seconds

5. **Recommendations Widget**

   - AI-powered energy-saving tips
   - kWh savings estimates
   - Cost savings projections

6. **Device Status Widget**
   - Current status of all devices
   - Real-time power consumption per device
   - Color-coded status indicators

#### Customization Features:

- Easy toggle switches in settings
- Persistent preferences
- Instant UI updates
- Drag-and-drop (future enhancement)

### 4. **AI-Powered Features**

#### Predictions

- Tomorrow's energy usage forecast
- Weekly and monthly forecasts
- Peak hours prediction
- Cost predictions
- Device-specific predictions

#### Recommendations

- Actionable energy-saving suggestions
- kWh-backed impact estimates
- Cost savings calculations
- Implementation steps

### 5. **Interactive Elements**

- **Pull-to-Refresh**: Update all dashboard data
- **Live Badge**: Shows real-time data status
- **Notification Bell**: Displays alert count
- **Customize Button**: Access widget settings
- **Expandable Cards**: View more details
- **Quick Actions**: One-tap access to details

## Services Architecture

### Energy Service

```dart
- getTodaySummary()
- getRealTimeConsumption()
- getEnergyData()
- getStatistics()
- getPeakHours()
- getCostBreakdown()
```

### Device Service

```dart
- getAllDevices()
- getRealTimeDeviceStatus()
- getDeviceConsumption()
- addDevice()
- updateDevice()
- deleteDevice()
```

### Anomaly Service

```dart
- getActiveAnomalies()
- getAllAnomalies()
- getAnomalyById()
- resolveAnomaly()
- getAnomalyStatistics()
- getSeverityCounts()
```

### Prediction Service

```dart
- getTomorrowPrediction()
- getWeeklyForecast()
- getMonthlyForecast()
- getPeakHoursPrediction()
- getCostPrediction()
- getRecommendations()
```

### Notification Service

```dart
- addNotification()
- markAsRead()
- markAllAsRead()
- showSnackBar()
- showNotificationDialog()
```

## Usage

### Basic Usage

```dart
import 'package:volt_guard/pages/enhanced_dashboard_page.dart';

// In your navigation or main app
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const EnhancedDashboardPage(),
  ),
);
```

### Customizing Widgets

1. Tap the **tune icon** (⚙️) in the app bar
2. Toggle widgets on/off using switches
3. Changes apply immediately
4. Preferences are saved

### Viewing Notifications

1. Check the **notification bell** icon for alert count
2. Tap to view all active anomalies
3. Each anomaly shows:
   - Device name
   - Description
   - Severity level
   - Timestamp

### Refreshing Data

- **Pull down** on the dashboard to refresh all widgets
- Data auto-refreshes every **30 seconds**
- **Live badge** indicates real-time status

## Visual Indicators

### Status Colors

- 🟢 **Green**: Normal operation, savings
- 🔵 **Blue**: Information, predictions
- 🟠 **Orange**: Warnings, medium priority
- 🔴 **Red**: Critical alerts, high consumption
- 🟣 **Purple**: Analytics, statistics
- 🟡 **Amber**: Predictions, insights

### Device Status

- 🟢 **Green dot**: Device ON/Active
- ⚫ **Grey dot**: Device OFF/Inactive
- 🟠 **Orange dot**: Warning state
- 🔵 **Blue dot**: Other states

## Performance Features

- **Lazy Loading**: Widgets load on demand
- **Caching**: Reduces API calls
- **Batch Requests**: Parallel data fetching
- **Silent Updates**: Background refreshes
- **Error Handling**: Graceful degradation
- **Retry Logic**: Automatic retry on failure

## Accessibility

- **Large Text**: Easy-to-read metrics
- **Color Contrast**: WCAG compliant
- **Icons**: Visual cues for all states
- **Clear Labels**: Descriptive text
- **Tap Targets**: Minimum 44x44 pts

## Future Enhancements

1. **WebSocket Integration**: True real-time updates
2. **Push Notifications**: Native mobile notifications
3. **Widget Reordering**: Drag-and-drop customization
4. **Custom Time Ranges**: User-defined periods
5. **Export Reports**: PDF/CSV generation
6. **Themes**: Light/dark mode
7. **Gamification**: Achievements and leaderboards
8. **Multi-Building Support**: Switch between locations
9. **Offline Mode**: Local caching
10. **Voice Alerts**: Audio notifications

## API Integration

The dashboard integrates with the following backend endpoints:

```
GET /api/v1/energy/today
GET /api/v1/energy/realtime
GET /api/v1/predictions/tomorrow
GET /api/v1/anomalies/active
GET /api/v1/devices/realtime
GET /api/v1/predictions/recommendations
```

## Error Handling

- Network errors: Retry button
- API errors: Error messages
- No data: Empty state UI
- Loading states: Progress indicators
- Timeout handling: Graceful degradation

## Best Practices

1. **Regular Updates**: Keep dashboard data fresh
2. **Monitor Alerts**: Act on anomalies promptly
3. **Review Predictions**: Plan ahead
4. **Follow Recommendations**: Implement savings tips
5. **Customize View**: Show relevant widgets only

## Support

For issues or questions:

- Check the error message details
- Verify backend API is running
- Check network connectivity
- Review API endpoint configurations

## Credits

Built with Flutter & FL Chart for visualization
