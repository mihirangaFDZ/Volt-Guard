"""
Zones router placeholder
Restores the FastAPI router object so the app can start.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/zones", tags=["zones"])


@router.get("/ping")
async def ping_zones():
	return {"status": "ok", "message": "zones router alive"}

