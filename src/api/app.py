"""
Travel Planner API - Azure Container Apps Backend

Combined API server and Durable Task Worker for the AI Travel Planner application.
This module provides HTTP endpoints for starting orchestrations, checking status,
and handling human-in-the-loop approval events.

Prerequisites:
- Set AZURE_OPENAI_ENDPOINT and AZURE_OPENAI_DEPLOYMENT_NAME
- Start a Durable Task Scheduler (e.g., using Docker)
"""

import json
import os
import logging
import threading
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from azure.identity import DefaultAzureCredential
from durabletask.azuremanaged.client import DurableTaskSchedulerClient

# Import worker components
from worker import (
    travel_planner_orchestration,
    destination_recommender_agent,
    itinerary_planner_agent,
    local_recommendations_agent,
    get_worker,
    setup_worker,
)
from agent_framework_durabletask import DurableAIAgentWorker

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration - read from environment
TASKHUB_NAME = os.getenv("TASKHUB_NAME", "default")

# Parse DTS connection string or use legacy DURABLE_TASK_HOST
DTS_CONNECTION_STRING = os.getenv("DURABLE_TASK_SCHEDULER_CONNECTION_STRING", "")
DURABLE_TASK_HOST = os.getenv("DURABLE_TASK_HOST", "localhost:8080")

def parse_dts_connection_string(conn_str: str) -> tuple[str, str | None]:
    """Parse DTS connection string to extract endpoint and client ID."""
    if not conn_str:
        return DURABLE_TASK_HOST, None
    parts = dict(part.split("=", 1) for part in conn_str.split(";") if "=" in part)
    endpoint = parts.get("Endpoint", DURABLE_TASK_HOST)
    client_id = parts.get("ClientID")
    return endpoint, client_id

DTS_ENDPOINT, DTS_CLIENT_ID = parse_dts_connection_string(DTS_CONNECTION_STRING)

logger.info(f"DTS Endpoint: {DTS_ENDPOINT}")
logger.info(f"TaskHub: {TASKHUB_NAME}")

# Durable Task client singleton
_dt_client: Optional[DurableTaskSchedulerClient] = None

# Worker singleton
_agent_worker: Optional[DurableAIAgentWorker] = None
_worker_thread: Optional[threading.Thread] = None


def get_durable_task_client() -> DurableTaskSchedulerClient:
    """Get or create the Durable Task client.
    
    Returns:
        Configured DurableTaskSchedulerClient instance
    """
    global _dt_client
    if _dt_client is None:
        endpoint_url = DTS_ENDPOINT
        
        logger.info(f"Creating DurableTaskSchedulerClient with endpoint: {endpoint_url}")
        
        # Use no credential for local emulator
        is_local = "localhost" in endpoint_url or "127.0.0.1" in endpoint_url
        credential = None if is_local else DefaultAzureCredential()
        
        _dt_client = DurableTaskSchedulerClient(
            host_address=endpoint_url,
            taskhub=TASKHUB_NAME,
            token_credential=credential,
            secure_channel=not is_local
        )
    return _dt_client


def start_worker():
    """Start the Durable Task worker in the current thread."""
    global _agent_worker
    try:
        # Create worker using the helper function
        worker = get_worker()
        
        # Setup worker with agents, orchestrations, and activities
        _agent_worker = setup_worker(worker)
        
        logger.info(f"Registered agents: {_agent_worker.registered_agent_names}")
        logger.info(f"Worker connecting to {DURABLE_TASK_HOST}...")
        
        _agent_worker.start()
        logger.info("Worker started successfully!")
    except Exception as e:
        logger.error(f"Failed to start worker: {e}")
        raise


def stop_worker():
    """Stop the Durable Task worker."""
    global _agent_worker
    if _agent_worker:
        logger.info("Stopping worker...")
        _agent_worker.stop()
        _agent_worker = None
        logger.info("Worker stopped")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler - starts worker on startup, stops on shutdown."""
    global _worker_thread
    
    logger.info("Starting Travel Planner API with embedded worker...")
    
    # Start the worker in a background thread
    _worker_thread = threading.Thread(target=start_worker, daemon=True)
    _worker_thread.start()
    
    # Give the worker a moment to connect
    import time
    time.sleep(1)
    
    yield
    
    logger.info("Shutting down Travel Planner API...")
    stop_worker()
    
    global _dt_client
    _dt_client = None


app = FastAPI(
    title="AI Travel Planner API",
    description="Backend API for orchestrating AI travel planning agents",
    version="1.0.0",
    lifespan=lifespan
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# Request/Response Models
class TravelRequest(BaseModel):
    """Travel planning request from frontend - matches the reference sample exactly."""
    userName: str = Field(default="", description="User's name")
    preferences: str = Field(default="", description="Travel preferences")
    durationInDays: int = Field(default=7, description="Trip duration in days")
    budget: str = Field(default="", description="Budget range")
    travelDates: str = Field(default="", description="Travel dates (e.g., July 1-11, 2025)")
    specialRequirements: str = Field(default="", description="Special requirements")


class StartWorkflowResponse(BaseModel):
    """Response after starting a workflow."""
    id: str
    status: str
    message: str


class WorkflowStatusResponse(BaseModel):
    """Response with workflow status - matches frontend expectations."""
    id: str
    step: str
    message: Optional[str] = None
    progress: Optional[int] = None
    destination: Optional[str] = None
    itinerary: Optional[str] = None
    finalPlan: Optional[str] = None
    documentUrl: Optional[str] = None
    travelPlan: Optional[dict] = None  # Contains the travel plan data for approval


class ApprovalResponse(BaseModel):
    """Response after approval/rejection."""
    id: str
    action: str
    message: str


# API Endpoints
@app.get("/health")
async def health_check():
    """Health check endpoint for Container Apps."""
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}


@app.get("/api/health")
async def api_health_check():
    """API health check endpoint."""
    return {
        "status": "healthy",
        "service": "travel-planner-api",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.post("/travel-planner", response_model=StartWorkflowResponse)
async def start_travel_planning(request: TravelRequest):
    """
    Start a new travel planning orchestration.
    
    This endpoint schedules a new orchestration instance with the Durable Task Scheduler.
    The orchestration will coordinate the specialized AI agents to create a travel plan.
    """
    try:
        client = get_durable_task_client()
        
        # Create input for the orchestration using the alias names expected by the worker
        input_data = {
            "userName": request.userName,
            "preferences": request.preferences,
            "durationInDays": request.durationInDays,
            "budget": request.budget,
            "travelDates": request.travelDates,
            "specialRequirements": request.specialRequirements
        }
        
        # Schedule the orchestration (synchronous call)
        instance_id = client.schedule_new_orchestration(
            travel_planner_orchestration,
            input=input_data
        )
        
        logger.info(f"Started travel planning orchestration: {instance_id}")
        
        return StartWorkflowResponse(
            id=instance_id,
            status="scheduled",
            message="Travel planning workflow has been started. Poll status endpoint for updates."
        )
        
    except Exception as e:
        logger.error(f"Failed to start travel planning: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to start travel planning: {str(e)}"
        )


@app.get("/travel-planner/status/{instance_id}", response_model=WorkflowStatusResponse)
async def get_travel_status(instance_id: str):
    """
    Get the status of a travel planning orchestration.
    
    This endpoint queries the orchestration status and returns current results.
    The frontend should poll this endpoint to check progress.
    """
    try:
        client = get_durable_task_client()
        
        # Get orchestration state (synchronous)
        state = client.get_orchestration_state(instance_id)
        
        if state is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Orchestration {instance_id} not found"
            )
        
        # Parse custom status for step info
        custom_status = state.serialized_custom_status or {}
        # Handle case where custom_status is a string (JSON)
        if isinstance(custom_status, str):
            try:
                custom_status = json.loads(custom_status)
            except json.JSONDecodeError:
                custom_status = {}
        step = custom_status.get("step", "Starting")
        message = custom_status.get("message", "Processing your travel plan...")
        progress = custom_status.get("progress", 10)
        destination = custom_status.get("destination")
        itinerary = custom_status.get("itinerary")
        travel_plan = custom_status.get("travelPlan")
        
        # Handle different runtime statuses
        runtime_status = str(state.runtime_status)
        
        final_plan = None
        if "COMPLETED" in runtime_status:
            step = "Completed"
            final_plan = state.serialized_output if isinstance(state.serialized_output, str) else str(state.serialized_output)
            progress = 100
        elif "FAILED" in runtime_status:
            step = "Error"
            message = "An error occurred during travel planning"
        elif "SUSPENDED" in runtime_status:
            step = "WaitingForApproval"
            progress = 100
        
        return WorkflowStatusResponse(
            id=instance_id,
            step=step,
            message=message,
            progress=progress,
            destination=destination,
            itinerary=itinerary,
            finalPlan=final_plan,
            documentUrl=custom_status.get("documentUrl"),
            travelPlan=travel_plan
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get travel status: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get travel status: {str(e)}"
        )


@app.post("/travel-planner/approve/{instance_id}", response_model=ApprovalResponse)
async def approve_travel_plan(instance_id: str):
    """
    Approve a travel plan.
    
    This endpoint raises an approval event to the orchestration,
    allowing it to resume from the human-in-the-loop wait state.
    """
    try:
        client = get_durable_task_client()
        
        # Raise the approval event to the orchestration (synchronous)
        client.raise_orchestration_event(
            instance_id,
            event_name="ApprovalEvent",
            data={
                "approved": True,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        logger.info(f"Travel plan {instance_id} approved")
        
        return ApprovalResponse(
            id=instance_id,
            action="approved",
            message="Travel plan has been approved. The workflow will continue processing."
        )
        
    except Exception as e:
        logger.error(f"Failed to process approval: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process approval: {str(e)}"
        )


@app.post("/travel-planner/reject/{instance_id}", response_model=ApprovalResponse)
async def reject_travel_plan(instance_id: str):
    """
    Reject a travel plan.
    
    This endpoint raises a rejection event to the orchestration.
    """
    try:
        client = get_durable_task_client()
        
        # Raise the approval event with rejected status (synchronous)
        client.raise_orchestration_event(
            instance_id,
            event_name="ApprovalEvent",
            data={
                "approved": False,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        logger.info(f"Travel plan {instance_id} rejected")
        
        return ApprovalResponse(
            id=instance_id,
            action="rejected",
            message="Travel plan has been rejected."
        )
        
    except Exception as e:
        logger.error(f"Failed to process rejection: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to process rejection: {str(e)}"
        )


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
