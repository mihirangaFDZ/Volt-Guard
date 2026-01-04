# backend/test_ml_endpoints.py
"""
Simple test script to verify ML model endpoints work correctly
Run this after starting the FastAPI server
"""
import requests
import json
from datetime import datetime

BASE_URL = "http://localhost:8000"

def print_section(title):
    print("\n" + "="*60)
    print(f"  {title}")
    print("="*60)

def test_endpoint(method, endpoint, params=None, data=None):
    """Test an endpoint and print results"""
    try:
        url = f"{BASE_URL}{endpoint}"
        
        if method == "GET":
            response = requests.get(url, params=params, timeout=30)
        elif method == "POST":
            response = requests.post(url, params=params, json=data, timeout=30)
        
        print(f"\n{method} {endpoint}")
        print(f"Status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print(f"Response: {json.dumps(result, indent=2)[:500]}...")  # Print first 500 chars
            return True, result
        else:
            print(f"Error: {response.text}")
            return False, None
            
    except requests.exceptions.ConnectionError:
        print(f"ERROR: Could not connect to {BASE_URL}")
        print("Make sure the FastAPI server is running!")
        return False, None
    except Exception as e:
        print(f"ERROR: {str(e)}")
        return False, None

def main():
    print_section("ML Endpoints Test Script")
    print("\nNote: This script tests endpoints WITHOUT authentication.")
    print("For full testing, you'll need to provide a JWT token.")
    print("\nTesting basic endpoints (may fail without auth)...")
    
    # Test 1: Health check (no auth needed)
    print_section("Test 1: Health Check")
    success, _ = test_endpoint("GET", "/health")
    
    # Test 2: Model Status (requires auth, but let's try)
    print_section("Test 2: Model Status")
    test_endpoint("GET", "/ml-training/status")
    
    # Test 3: Model Info (requires auth)
    print_section("Test 3: Model Information")
    test_endpoint("GET", "/ml-training/model-info")
    
    print_section("Testing Complete")
    print("\nNote: Endpoints requiring authentication will return 401/403 errors")
    print("To test with authentication:")
    print("1. Get a JWT token from /auth/login")
    print("2. Add 'Authorization: Bearer <token>' header to requests")
    print("\nOr use the FastAPI interactive docs at:")
    print(f"  {BASE_URL}/docs")

if __name__ == "__main__":
    main()

