from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from routes import devices, energy, prediction, anomalies, user_routes, analytics, zones, faults
from routes.auth_routes import router as auth_router


import os

app = FastAPI(
    title="Volt Guard API",
    description="Smart Energy Management System using IoT and AI",
    version="1.0.0"
)

# Configure CORS with environment-aware settings
# For production, set ALLOWED_ORIGINS environment variable
allowed_origins = os.getenv("ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:8080").split(",")

# In development, allow all origins for easier testing
if os.getenv("DEBUG", "False").lower() == "true":
    allowed_origins = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "Welcome to Volt Guard API",
        "version": "1.0.0",
        "description": "Smart Energy Management System using IoT and AI"
    }

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy"}


app.include_router(auth_router)
app.include_router(zones.router)
app.include_router(devices.router)
app.include_router(energy.router)
app.include_router(prediction.router)
app.include_router(anomalies.router)
app.include_router(user_routes.router)
app.include_router(analytics.router)
app.include_router(faults.router)
