# Durable Task Extension for Agent Framework — Travel Planner

Extracted from [Azure Sample for Durable Task Extension for Agent Framework](https://github.com/Azure-Samples/durable-task-extension-for-agent-framework/tree/main/samples/python/azure-container-apps/agentic-travel-planner), focusing just on the Python code and updated for latest dependencies. 


## Description 

An agentic travel planner built with the [Microsoft Agent Framework](https://github.com/microsoft/agent-framework) and [Durable Task Scheduler](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-task-scheduler/), deployed to Azure Container Apps.

Three specialised AI agents collaborate through a durable orchestration to produce a complete travel plan with human-in-the-loop approval.

## Architecture

```
React Frontend ──► FastAPI Backend ──► Durable Task Scheduler
                        │
            ┌───────────┼───────────┐
            ▼           ▼           ▼
      Destination   Itinerary    Local Guide
        Agent         Agent        Agent
```

**Workflow:** User request → destination recommendations → itinerary planning → local tips → human approval → booking confirmation.

## Prerequisites

- Python 3.11+ with [Poetry](https://python-poetry.org/)
- [Docker](https://www.docker.com/) (for the DTS emulator)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) (`az login`)
- An Azure OpenAI resource with a GPT-4.1 (or similar) deployment

## Quick Start

```bash
# 1. Provision Azure resources (OpenAI, DTS, Storage — includes RBAC)
make provision      # runs azd provision

# 2. Setup environment and install dependencies
make setup          # creates .env (auto-populated from azd) + installs deps

# 3. Start local infrastructure
make emulator       # DTS emulator on localhost:8080

# 4. Start the API (in one terminal)
make api            # FastAPI on localhost:8000

# 5. Start the frontend (in another terminal)
make frontend       # React on localhost:3000
```

Open http://localhost:3000 or use the Swagger UI at http://localhost:8000/docs.

## Make Targets

```
make help           Show all available targets
make provision      Provision Azure resources (OpenAI, DTS, Storage + RBAC)
make setup          Full local setup (env + dependencies)
make env            Create .env from template (auto-populates from azd if available)
make install        Install Python and Node dependencies
make role           Assign OpenAI RBAC role to current user
make emulator       Start DTS emulator (Docker)
make azurite        Start Azurite storage emulator
make local-infra    Start all local infrastructure (emulators)
make api            Start the backend API
make frontend       Start the React frontend
make deploy         Deploy app to Azure Container Apps
make clean          Stop and remove the DTS emulator
```

## Testing via API

The orchestration runs through 3 AI agents then pauses for human approval before booking. Here's the full end-to-end flow:

### 1. Start a travel plan

```bash
curl -s -X POST http://localhost:8000/travel-planner \
  -H "Content-Type: application/json" \
  -d '{
    "userName": "Carlos",
    "preferences": "Beach and culture, local food",
    "durationInDays": 5,
    "budget": "$3000",
    "travelDates": "March 2026",
    "specialRequirements": "None"
  }'
```

Response (save the `id`):
```json
{
  "id": "abc123...",
  "status": "scheduled",
  "message": "Travel planning workflow has been started..."
}
```

### 2. Poll for status

The orchestration progresses through these steps: `GettingDestinations` → `CreatingItinerary` → `GettingLocalRecommendations` → `WaitingForApproval`. Poll until it reaches `WaitingForApproval`:

```bash
curl -s http://localhost:8000/travel-planner/status/{id} | python3 -m json.tool
```

This typically takes 30–60 seconds. The `step` field shows current progress. Once it reaches `WaitingForApproval`, the response includes a full `travelPlan` object with the destination, daily itinerary, attractions, restaurants, and insider tips.

### 3. Approve (or reject) the plan

Once the status shows `WaitingForApproval`, the orchestration is paused waiting for a human decision:

```bash
# Approve — triggers booking
curl -s -X POST http://localhost:8000/travel-planner/approve/{id}

# Or reject
curl -s -X POST http://localhost:8000/travel-planner/reject/{id}
```

### 4. Check final result

After approval, poll status one more time. The step will be `Completed` with a booking confirmation:

```bash
curl -s http://localhost:8000/travel-planner/status/{id} | python3 -m json.tool
```

The `finalPlan` field contains the full result including `BookingConfirmation` with a confirmation ID (e.g. `TRV-469055`).

If rejected, the step will be `Rejected` and no booking is created. If no approval arrives within 24 hours, the orchestration times out automatically.

### Using the REST Client

You can also use the [test.http](src/api/test.http) file with the VS Code REST Client extension, or the Swagger UI at http://localhost:8000/docs.

## Project Structure

```
├── Makefile                        # Dev workflow commands
├── scripts/
│   └── assign-openai-role.sh       # Azure RBAC role assignment
├── azure.yaml                      # Azure Developer CLI config
├── infra/                          # Bicep IaC for Azure deployment
│   ├── main.bicep                  # Main template (OpenAI, DTS, Container Apps)
│   └── app/dts.bicep               # Durable Task Scheduler module
├── src/
│   ├── .env.template               # Environment config template
│   ├── api/                        # FastAPI backend
│   │   ├── app.py                  # HTTP endpoints + worker lifecycle
│   │   ├── worker.py               # Agents, orchestration, activities
│   │   ├── models/                 # Pydantic response models
│   │   ├── tools/                  # Agent tools (currency converter)
│   │   └── pyproject.toml          # Poetry dependencies
│   └── frontend/                   # React SPA
└── quickstarts/                    # Reference quickstart samples
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `agent-framework-core` | Microsoft Agent Framework |
| `agent-framework-durabletask` | Durable Task integration for agents |
| `durabletask` / `durabletask-azuremanaged` | Durable Task SDK |
| `fastapi` / `uvicorn` | HTTP API server |
| `azure-identity` | Azure authentication (DefaultAzureCredential) |

## Deploy to Azure

```bash
azd auth login
azd up           # provisions infra + deploys app
```

## Learn More

- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [Agent Framework Python Migration Guide](https://learn.microsoft.com/en-us/agent-framework/support/upgrade/python-2026-significant-changes)
- [Durable Task Scheduler](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-task-scheduler/)
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/)


## Summary of fixes to the original repo 

3 types of fix:

1. `@tool` decorator now required — `currency_converter.py`

Added from agent_framework import tool
Added @tool decorator to get_exchange_rate() and convert_currency()
The newer SDK (1.0.0b260212) requires explicit tool registration via the decorator; the old version (0.0.2b260126) did not.

2. `get_new_thread()` → `create_session()` — `worker.py`

6 occurrences: destination_agent.get_new_thread() → .create_session(), same for itinerary_agent and local_agent
Corresponding thread= keyword argument renamed to session= in agent.run() calls

3. `try_parse_value()` → `.value` property — `worker.py`

The old result.try_parse_value(model_class) method was removed from the SDK
Replaced with accessing result.value and using isinstance() to type-check, with fallback to raw text JSON parsing