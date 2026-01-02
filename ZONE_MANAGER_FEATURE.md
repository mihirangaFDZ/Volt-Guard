# Smart Zone Energy Manager - Implementation Guide

## Overview
The **Smart Zone Energy Manager** is a powerful new feature for Volt Guard that allows users (like tuition institutes) to manage energy consumption across multiple zones/rooms with real-time monitoring, automation rules, and cost tracking.

## ✨ Core Features Implemented

### 1. **Zone Management Dashboard** 🏢
**File**: [lib/pages/zones_page.dart](lib/pages/zones_page.dart)

**Features:**
- View all zones for your organization
- Summary statistics:
  - Total power usage (kW)
  - Total monthly cost
  - Occupied vs empty zones
  - Total connected devices
- Quick action buttons:
  - **All Off**: Turn off all devices in all zones
  - **All On**: Turn on all devices in all zones
  - **Power Saver**: Activate energy-saving mode across zones
- Zone cards showing:
  - Zone name, type, floor, occupancy status
  - Current power consumption
  - Monthly consumption (kWh)
  - Monthly cost with budget tracking
  - Color-coded budget alerts (Green/Yellow/Red)

### 2. **Zone Details & Device Management** 📍
**File**: [lib/pages/zone_details_page.dart](lib/pages/zone_details_page.dart)

**Tab 1: Devices**
- List all devices in the zone
- Device information:
  - Device name and type
  - Power consumption (watts)
  - Status (ON/OFF)
  - Energy consumed today
- One-tap device control
- Add new devices to zone

**Tab 2: Schedules (Automation Rules)**
- Create automated rules for device control
- Rule configuration:
  - Rule name & description
  - Days of week (Mon-Fri, etc.)
  - Start & end time
  - Action (ON, OFF, POWER_SAVER)
  - Target devices
- Example rules:
  - "School Hours": AC ON 8:00-15:00 (Mon-Fri)
  - "Evening Lights Off": Lights OFF 16:00-07:00
  - "Weekend Energy Saver": All devices power saver mode

**Tab 3: Analytics**
- Zone performance metrics:
  - Peak power usage
  - Monthly consumption trends
  - Monthly cost vs budget
  - Device efficiency rating
  - Cost projections
  - AI recommendations for savings

---

## 🔧 Backend Implementation

### Database Models
**File**: [backend/app/models/zone_model.py](backend/app/models/zone_model.py)

**Models:**
```python
- Zone: Complete zone/room entity
- DeviceInZone: Device reference with power info
- ScheduleRule: Automation rule configuration
- ZoneCreate/Update: Request schemas
- ZoneResponse: API response schema
- ZoneSummary: Organization-wide summary
```

**Zone Properties:**
- `zone_id`, `zone_name`, `zone_type` (Classroom, Lab, Office, etc.)
- `floor_number`, `location`, `area_sq_meters`, `capacity`
- `devices[]`: List of connected devices
- `schedule_rules[]`: Automation rules
- `current_power_usage`, `monthly_consumption`, `monthly_cost`
- `monthly_budget`, `occupancy_status`
- `power_threshold`, `cost_threshold` for alerts

### API Endpoints
**File**: [backend/routes/zones.py](backend/routes/zones.py)

**CRUD Operations:**
```
POST   /api/v1/zones                          - Create new zone
GET    /api/v1/zones                          - Get all zones for organization (with summary)
GET    /api/v1/zones/{zone_id}               - Get zone details
PUT    /api/v1/zones/{zone_id}               - Update zone
DELETE /api/v1/zones/{zone_id}               - Delete zone (soft delete)
```

**Device Management:**
```
POST   /api/v1/zones/{zone_id}/devices       - Add device to zone
DELETE /api/v1/zones/{zone_id}/devices/{id}  - Remove device from zone
```

**Schedule Management:**
```
POST   /api/v1/zones/{zone_id}/schedule-rules      - Create automation rule
DELETE /api/v1/zones/{zone_id}/schedule-rules/{id} - Delete rule
```

**Operations:**
```
PUT    /api/v1/zones/{zone_id}/occupancy                   - Update occupancy status
GET    /api/v1/zones/{zone_id}/cost-analysis              - Get cost breakdown & recommendations
POST   /api/v1/zones/{zone_id}/power-control              - Quick control (all_on/off, power_saver)
```

---

## 📱 Frontend Integration

### Updated Navigation
The main navigation now includes **6 tabs**:
1. **Dashboard** - Overview of all energy data
2. **Zones** ⭐ **NEW** - Zone management and quick controls
3. **Devices** - Individual device management
4. **Analytics** - Historical data and insights
5. **Faults** - Anomaly detection alerts
6. **Profile** - User settings and account

### State Management (Ready for Implementation)
Currently using mock data. Next step: Integrate with actual API using:
- **Provider** package for state management
- **http** package for API calls
- **shared_preferences** for caching zone data

---

## 🎯 Use Cases for B2B (Tuition Institute Example)

### Principal/Admin View
✅ Monitor all classroom energy usage at a glance  
✅ Set monthly energy budgets per room  
✅ Get alerts when budget is exceeded  
✅ Control all rooms from admin dashboard  
✅ See which rooms are wasting energy  
✅ Generate cost reports for accounting  

### Facility Manager View
✅ Create automation schedules (AC ON at 8AM, OFF at 5PM)  
✅ Control devices remotely without visiting room  
✅ Monitor device health and predict failures  
✅ Receive alerts for unusual power consumption  
✅ Optimize schedules based on usage patterns  

### Teaching Staff View
✅ See energy cost of their classroom  
✅ Adjust temperature/lighting as needed  
✅ Quick access to device controls  

---

## 💡 Innovative Features Highlights

### 1. **Multi-Zone Centralized Control**
- Manage all zones from one dashboard
- Quick actions affect entire facility at once
- Cost visibility across zones

### 2. **Smart Automation Rules**
- No coding required - simple UI to create rules
- Time-based schedules (weekdays, specific hours)
- Easy to edit and disable rules

### 3. **Budget Tracking**
- Set monthly budget per zone
- Real-time budget status with visual indicators
- Warnings before exceeding budget
- Historical cost analysis

### 4. **Occupancy Integration** ⚡
- Detect when rooms are empty
- Auto-trigger power-saving rules
- Reduce unnecessary energy consumption

### 5. **Cost Allocation**
- Detailed breakdown of costs by:
  - Zone (which room costs most)
  - Device type (AC, lighting, equipment)
  - Time period (daily, weekly, monthly)
- Perfect for billing departments

### 6. **AI Recommendations** 🤖
- System suggests optimal schedules
- Identifies energy waste patterns
- Recommends device replacements
- Predicts future costs

---

## 🚀 Implementation Roadmap

### Phase 1: ✅ **Completed** (Current)
- Backend Zone models and API endpoints
- Frontend Zones dashboard and details pages
- Navigation integration
- Mock data with realistic scenarios

### Phase 2: **Next** (Recommended)
1. Connect to real backend API
2. Implement state management with Provider
3. Add real-time data updates
4. Store user preferences locally

### Phase 3: **Advanced Features**
1. MQTT integration for real device control
2. Push notifications for alerts
3. Advanced analytics with charts (fl_chart)
4. ML-based recommendations
5. Biometric auth for quick control
6. Dark mode support
7. Multi-language support

### Phase 4: **Enterprise**
1. User role-based access control
2. Audit logs for compliance
3. Advanced reporting and export
4. Integration with building management systems
5. Mobile app offline mode
6. Two-factor authentication

---

## 📊 API Response Examples

### Get All Zones
```json
{
  "total_zones": 4,
  "active_zones": 4,
  "total_devices": 20,
  "total_power_usage": 9900,
  "daily_cost": 118.8,
  "monthly_consumption": 450,
  "zones": [
    {
      "zone_id": "zone_1",
      "zone_name": "Classroom A",
      "current_power_usage": 2400,
      "monthly_cost": 1800,
      "monthly_budget": 2000,
      "device_count": 5,
      "occupancy_status": "occupied"
    }
  ]
}
```

### Zone Cost Analysis
```json
{
  "zone_id": "zone_1",
  "zone_name": "Classroom A",
  "current_cost": 1800,
  "budget": 2000,
  "budget_remaining": 200,
  "budget_percentage": 90,
  "device_breakdown": {
    "Air Conditioner": 1080,
    "Lighting": 480,
    "Equipment": 240
  },
  "projections": {
    "projected_monthly_cost": 1980,
    "days_until_budget_exceeded": 15
  },
  "recommendations": [
    "Consider reducing AC usage during off-peak hours",
    "LED lights can save up to 70% energy",
    "Set device schedules to reduce idle time"
  ]
}
```

---

## 📝 Configuration

### Backend Setup
```bash
# Already integrated in app/main.py
# Zone routes available at /api/v1/zones
# CORS enabled for frontend connection
```

### Frontend Setup
```dart
// API Config in lib/services/api_config.dart
static const String baseUrl = 'http://10.0.2.2:8000';
static const String apiVersion = '/api/v1';

// Usage in zones_page.dart (uncomment when backend ready)
// final response = await http.get(Uri.parse('$apiBaseUrl/zones?organization_id=...');
```

---

## 🎓 Training Points for Your Team

### For Developers
- How zone models relate to energy calculations
- API endpoint design patterns
- State management best practices
- Real-time data handling

### For Clients (Institute Admins)
- How to create and manage zones
- Setting up automation rules effectively
- Understanding cost reports
- Using quick controls for emergency situations

### For End Users (Teachers/Staff)
- Simple one-tap device control
- Understanding occupancy status
- Recognizing budget warnings
- Using preset rules instead of manual control

---

## 📞 Support & Next Steps

**Questions to address:**
1. Should we add occupancy sensors integration (PIR, door sensors)?
2. Do we need email alerts for budget exceeded?
3. Should scheduling support multiple rules per device?
4. Need integration with existing IoT protocols (MQTT, Zigbee)?

**To test the feature:**
1. Run backend: `uvicorn app.main:app --reload`
2. Run frontend: `flutter run`
3. Navigate to "Zones" tab
4. Mock data will populate automatically
5. Once API is ready, uncomment API calls and remove mock data

---

## 🏆 Why This Feature Wins

✅ **Solves Real Problems**: Institutions have many rooms - they need centralized control  
✅ **Shows ROI**: Clear cost tracking demonstrates energy savings  
✅ **Easy to Use**: No technical knowledge needed  
✅ **Scalable**: Works for 5 rooms or 500 rooms  
✅ **Innovative**: Most energy apps target homes, not businesses  
✅ **Professional**: Enterprise-grade features at competitive price  

---

## 📈 Market Differentiation

**Competitors typically offer:**
- Individual device control only
- No zone/room aggregation
- No budget tracking
- Manual controls only

**Volt Guard Zone Manager offers:**
- ✨ Multi-zone centralized control
- 💰 Budget tracking per zone
- 🤖 Smart automation rules
- 📊 Detailed cost analytics
- 🎯 Quick actions for entire facility
- 🏢 Perfect for B2B sales

This makes Volt Guard a complete **Energy Management Suite** rather than just a monitoring app!
