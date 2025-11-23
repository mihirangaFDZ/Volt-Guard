from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="Volt Guard API",
    description="Smart Energy Management System using IoT and AI",
    version="1.0.0"
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
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

# Import routers (to be added)
# from app.api import energy, devices, predictions, anomalies
# app.include_router(energy.router, prefix="/api/v1/energy", tags=["energy"])
# app.include_router(devices.router, prefix="/api/v1/devices", tags=["devices"])
# app.include_router(predictions.router, prefix="/api/v1/predictions", tags=["predictions"])
# app.include_router(anomalies.router, prefix="/api/v1/anomalies", tags=["anomalies"])
