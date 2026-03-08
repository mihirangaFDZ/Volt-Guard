"""
Volt Guard AI Chatbot API - answers from DB data + FAQ, suggestions, custom dataset.
"""

import asyncio
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.services.volt_guard_chatbot import get_chatbot
from utils.jwt_handler import get_current_user

router = APIRouter(prefix="/chatbot", tags=["Chatbot"])


class ChatRequest(BaseModel):
    message: str


class ChatResponse(BaseModel):
    response: str
    confidence: float
    status: str = "success"
    suggestions: List[str] = []


@router.post("/chat", response_model=ChatResponse)
async def chat(
    body: ChatRequest,
    _user=Depends(get_current_user),
):
    """
    Send a message. Bot uses database data when relevant, else FAQ/custom Q&A.
    Returns answer + suggested follow-up questions.
    """
    if not body.message or not body.message.strip():
        raise HTTPException(status_code=400, detail="Message cannot be empty")
    try:
        bot = await asyncio.to_thread(get_chatbot)
        answer, confidence, suggestions = await asyncio.to_thread(
            bot.get_response, body.message.strip(), 0.2, 1
        )
    except Exception as e:
        raise HTTPException(
            status_code=503,
            detail=f"Chatbot not available: {e}",
        )
    return ChatResponse(
        response=answer,
        confidence=round(confidence, 4),
        suggestions=suggestions or [],
    )


@router.get("/suggestions")
async def get_suggestions(
    limit: int = 4,
    _user=Depends(get_current_user),
):
    """Get suggested questions for the user."""
    try:
        bot = await asyncio.to_thread(get_chatbot)
        suggestions = await asyncio.to_thread(bot.get_suggestions, limit)
        return {"suggestions": suggestions}
    except Exception as e:
        return {"suggestions": [], "error": str(e)}


# --- Custom dataset (add/update Q&A) ---

class AddDatasetEntryRequest(BaseModel):
    question: str
    answer: str


@router.post("/dataset")
async def add_dataset_entry(
    body: AddDatasetEntryRequest,
    _user=Depends(get_current_user),
):
    """Add a custom question-answer pair. The chatbot will use it in future replies."""
    if not body.question or not body.question.strip():
        raise HTTPException(status_code=400, detail="Question is required")
    if not body.answer or not body.answer.strip():
        raise HTTPException(status_code=400, detail="Answer is required")
    try:
        bot = await asyncio.to_thread(get_chatbot)
        result = await asyncio.to_thread(
            bot.add_custom_qa, body.question.strip(), body.answer.strip()
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    if not result.get("ok"):
        raise HTTPException(status_code=400, detail=result.get("error", "Failed to add"))
    return result


@router.get("/dataset")
async def list_dataset_entries(
    _user=Depends(get_current_user),
):
    """List custom Q&A entries you have added."""
    try:
        bot = await asyncio.to_thread(get_chatbot)
        entries = await asyncio.to_thread(bot.list_custom_qa)
        return {"entries": entries}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/dataset/{entry_id}")
async def delete_dataset_entry(
    entry_id: str,
    _user=Depends(get_current_user),
):
    """Delete a custom Q&A entry by id."""
    try:
        bot = await asyncio.to_thread(get_chatbot)
        result = await asyncio.to_thread(bot.delete_custom_qa, entry_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    if not result.get("ok"):
        raise HTTPException(status_code=400, detail=result.get("error", "Failed to delete"))
    return result


@router.get("/health")
async def chatbot_health():
    """Check if the chatbot is loaded and ready (no auth required for health)."""
    try:
        bot = get_chatbot()
        ready = (bot.vectorizer is not None and bot.question_vectors is not None) or len(bot.questions) == 0
        return {
            "status": "healthy" if ready else "not_ready",
            "model_loaded": ready,
            "dataset_size": len(bot.questions) if bot.questions else 0,
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "model_loaded": False,
        }
