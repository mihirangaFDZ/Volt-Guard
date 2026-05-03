# backend/test_behavioral_profiles.py
"""
Test script for behavioral profiling & energy vampire detection endpoints.

Usage:
    1. Start the server:     cd backend && python -m uvicorn app.main:app --reload
    2. Seed test data:       python seed_test_data.py
    3. Run this script:      python test_behavioral_profiles.py

    Or provide a JWT token:  python test_behavioral_profiles.py --token <your_jwt>
"""
import requests
import json
import sys

BASE_URL = "http://localhost:8000"
TOKEN = None


def print_section(title):
    print("\n" + "=" * 60)
    print(f"  {title}")
    print("=" * 60)


def get_headers():
    if TOKEN:
        return {"Authorization": f"Bearer {TOKEN}"}
    return {}


def get_token():
    """Try to log in with a test account to get a JWT token."""
    try:
        resp = requests.post(f"{BASE_URL}/auth/login", json={
            "email": "test@test.com",
            "password": "test1234"
        }, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            return data.get("access_token") or data.get("token")
    except:
        pass

    # Try registering first
    try:
        requests.post(f"{BASE_URL}/auth/register", json={
            "name": "Test User",
            "email": "test@test.com",
            "password": "test1234"
        }, timeout=5)
        resp = requests.post(f"{BASE_URL}/auth/login", json={
            "email": "test@test.com",
            "password": "test1234"
        }, timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            return data.get("access_token") or data.get("token")
    except:
        pass

    return None


def test(method, endpoint, params=None):
    """Make a request and print the result."""
    try:
        url = f"{BASE_URL}{endpoint}"
        headers = get_headers()

        if method == "GET":
            resp = requests.get(url, params=params, headers=headers, timeout=30)
        else:
            resp = requests.post(url, params=params, headers=headers, timeout=30)

        print(f"\n{method} {endpoint}")
        if params:
            print(f"Params: {params}")
        print(f"Status: {resp.status_code}")

        if resp.status_code == 200:
            data = resp.json()
            print(json.dumps(data, indent=2, default=str))
            return True, data
        else:
            print(f"Error: {resp.text[:300]}")
            return False, None

    except requests.exceptions.ConnectionError:
        print(f"\nERROR: Cannot connect to {BASE_URL}")
        print("Make sure the server is running: python -m uvicorn app.main:app --reload")
        return False, None
    except Exception as e:
        print(f"\nERROR: {e}")
        return False, None


def main():
    global TOKEN

    print_section("Behavioral Profile & Energy Vampire Test Suite")

    # Get token
    if TOKEN is None:
        print("\nAttempting to get JWT token...")
        TOKEN = get_token()
        if TOKEN:
            print(f"Got token: {TOKEN[:20]}...")
        else:
            print("WARNING: Could not get token. Endpoints may return 401.")
            print("Use --token <jwt> or ensure a test user exists.\n")

    # ---------------------------------------------------------------
    # Test 1: Health check
    # ---------------------------------------------------------------
    print_section("1. Health Check")
    test("GET", "/health")

    # ---------------------------------------------------------------
    # Test 2: Get all behavioral profiles
    # ---------------------------------------------------------------
    print_section("2. All Behavioral Profiles (7-day window)")
    ok, data = test("GET", "/behavioral-profiles/", {"hours_back": 168})

    if ok and data:
        total = data.get("total_devices", 0)
        print(f"\n>>> Found {total} device profiles")
        for p in data.get("profiles", []):
            flag = "VAMPIRE" if p["is_energy_vampire"] else "ok"
            print(f"    {p['device_id']:20s}  occupied={p['avg_power_occupied']:7.1f}W  "
                  f"vacant={p['avg_power_vacant']:7.1f}W  "
                  f"standby_ratio={p['standby_ratio']:.2%}  [{flag}]")

    # ---------------------------------------------------------------
    # Test 3: Energy vampires only
    # ---------------------------------------------------------------
    print_section("3. Energy Vampires")
    ok, data = test("GET", "/behavioral-profiles/energy-vampires", {"hours_back": 168})

    if ok and data:
        print(f"\n>>> {data.get('total_vampires', 0)} vampires detected")
        print(f">>> Total energy waste: {data.get('total_energy_waste_kwh', 0):.4f} kWh")
        for v in data.get("vampires", []):
            print(f"    {v['device_id']:20s}  idle={v['avg_power_vacant']:.1f}W  "
                  f"waste={v['energy_waste_kwh']:.4f} kWh  severity={v['vampire_severity']}")

    # ---------------------------------------------------------------
    # Test 4: Single device profile
    # ---------------------------------------------------------------
    print_section("4. Single Device Profile (TEST_AC_01)")
    ok, data = test("GET", "/behavioral-profiles/TEST_AC_01", {"hours_back": 168})

    if ok and data:
        print(f"\n>>> Hourly profile (first 6 hours):")
        for h in data.get("hourly_profile", [])[:6]:
            bar = "#" * int(h["avg_power_w"] / 20)
            print(f"    {h['hour']:2d}:00  {h['avg_power_w']:7.1f}W  {bar}")
        print(f"    ...")

    # ---------------------------------------------------------------
    # Test 5: Filter by location
    # ---------------------------------------------------------------
    print_section("5. Profiles Filtered by Location (LAB_1)")
    test("GET", "/behavioral-profiles/", {"hours_back": 168, "location": "LAB_1"})

    # ---------------------------------------------------------------
    # Test 6: Non-existent device (expect 404)
    # ---------------------------------------------------------------
    print_section("6. Non-existent Device (expect 404)")
    test("GET", "/behavioral-profiles/FAKE_DEVICE")

    # ---------------------------------------------------------------
    # Test 7: Anomaly detection (Isolation Forest)
    # ---------------------------------------------------------------
    print_section("7. Anomaly Detection — Isolation Forest")
    test("GET", "/anomalies/detect", {"hours_back": 24, "method": "isolation_forest"})

    # ---------------------------------------------------------------
    # Test 8: Anomaly detection (Autoencoder)
    # ---------------------------------------------------------------
    print_section("8. Anomaly Detection — Autoencoder")
    test("GET", "/anomalies/detect", {"hours_back": 24, "method": "autoencoder"})

    # ---------------------------------------------------------------
    # Test 9: LSTM Prediction
    # ---------------------------------------------------------------
    print_section("9. LSTM Prediction")
    test("GET", "/prediction/predict", {"location": "LAB_1", "hours_ahead": 6})

    # ---------------------------------------------------------------
    # Test 10: ML Training Status
    # ---------------------------------------------------------------
    print_section("10. ML Training Status")
    test("GET", "/ml-training/status")

    print_section("Tests Complete")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--token", type=str, help="JWT token for authentication")
    args = parser.parse_args()

    if args.token:
        TOKEN = args.token

    main()
