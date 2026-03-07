from pymongo import MongoClient

uri = "mongodb+srv://menda:menda@clustermendis.eqm7p.mongodb.net/?retryWrites=true&w=majority&appName=Clustermendis"
client = MongoClient(uri)
db = client["voltguard"]

devices = list(db["devices"].find({}, {"_id": 0, "device_name":1, "rated_power_watts": 1, "device_type": 1}))
print(f"Found {len(devices)} devices:")

TYPICAL_DAILY_HOURS = {"ac": 10, "refrigerator": 24, "water heater": 4, "washing machine": 2, "light": 8, "fan": 12}

total = 0.0
for d in devices:
    rated = d.get("rated_power_watts", 0)
    dtype = (d.get("device_type") or "").lower()
    hours = TYPICAL_DAILY_HOURS.get(dtype, 8.0)
    kwh = (rated * hours) / 1000.0
    total += kwh
    print(f" - {d.get('device_name')}: {rated}W, Type: {dtype}, Hours: {hours} -> {kwh:.2f} kWh/day")

print(f"\nTOTAL BASELINE: {total:.2f} kWh/day")
