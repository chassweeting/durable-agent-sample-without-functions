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

```bash
# Start a travel plan
curl -X POST http://localhost:8000/travel-planner \
  -H "Content-Type: application/json" \
  -d '{
    "userName": "Carlos",
    "preferences": "Windsurfing holiday, guaranteed wind, warm water, healthy food, not crowded",
    "durationInDays": 15,
    "budget": "$8000",
    "travelDates": "July, 2026",
    "specialRequirements": "Ion club windsurf rental"
  }'

# Check status (use the id from the response above)
curl http://localhost:8000/travel-planner/status/{id}

# Approve the plan
curl -X POST http://localhost:8000/travel-planner/approve/{id}
```

Or use the Swagger UI at http://localhost:8000/docs, or the [test.http](src/api/test.http) file with the VS Code REST Client extension.

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
