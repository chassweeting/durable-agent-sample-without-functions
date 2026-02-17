# Original repo docuemntation : 


## AI Travel Planner - Azure Container Apps

A travel planning application that demonstrates how to build **durable AI agents** using the [Durable Task extension for Microsoft Agent Framework](https://github.com/microsoft/agent-framework). The application coordinates multiple specialized AI agents to create comprehensive, personalized travel plans through a structured workflow, deployed to Azure Container Apps.

## Overview

This sample showcases an **agentic workflow** where specialized AI agents collaborate to plan travel experiences. Each agent focuses on a specific aspect of travel planning—destination recommendations, itinerary creation, and local insights—orchestrated by the Durable Task extension for reliability and state management.

### Why Durable Agents?

Traditional AI agents can be unpredictable and inconsistent. The Durable Task extension solves this by providing:

- **Deterministic workflows**: Pre-defined steps ensure consistent, high-quality results
- **Built-in resilience**: Automatic state persistence and recovery from failures
- **Human-in-the-loop**: Native support for approval workflows before booking
- **Scalability**: Serverless execution that scales with demand

## Architecture

```
┌─────────────┐     HTTP Request      ┌─────────────────────┐
│   React     │ ──────────────────▶  │  Backend API        │
│  Frontend   │                       │  (Container App)    │
│ (Container  │ ◀────────────────────│                     │
│    App)     │    Status/Results     │  - Schedule         │
└─────────────┘                       │    Orchestration    │
                                      │  - Query Status     │
                                      │  - Send Approval    │
                                      └─────────┬───────────┘
                                                │
                                    Schedules & Manages
                                                │
                                                ▼
                                      ┌─────────────────────┐
                                      │  Durable Task       │
                                      │  Scheduler          │
                                      │                     │
                                      │  Orchestration:     │
                                      │  travel_workflow    │
                                      └─────────┬───────────┘
                                                │
                                    Coordinates Agents
                                                │
                    ┌───────────────────────────┼───────────────────────────┐
                    ▼                           ▼                           ▼
          ┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
          │  Destination    │         │   Itinerary     │         │  Local Guide    │
          │     Agent       │         │     Agent       │         │     Agent       │
          └─────────────────┘         └─────────────────┘         └─────────────────┘
```

### Workflow

1. **User Request** → User submits travel preferences via React frontend
2. **Schedule Orchestration** → Frontend calls Backend API, which schedules a new orchestration
3. **Destination Recommendation** → AI agent analyzes preferences and suggests destinations
4. **Itinerary Planning** → AI agent creates detailed day-by-day plans
5. **Local Recommendations** → AI agent adds insider tips and attractions
6. **Storage** → Travel plan saved to Azure Blob Storage
7. **Wait for Approval** → Orchestration pauses for human-in-the-loop approval
8. **User Approval** → User approves/rejects via Frontend
9. **Booking** → Upon approval, booking process completes

### Tech Stack

| Component | Technology |
|-----------|------------|
| **Backend** | Python 3.11, Azure Container Apps |
| **AI Framework** | Microsoft Agent Framework with Durable Task Extension |
| **Orchestration** | Durable Task Scheduler |
| **AI Model** | Azure OpenAI (GPT-4.1) |
| **Frontend** | React (hosted in Container App) |
| **Storage** | Azure Blob Storage |
| **Infrastructure** | Bicep, Azure Developer CLI (azd) |

## Prerequisites

Before you begin, ensure you have the following installed:

- [Python 3.11](https://www.python.org/downloads/)
- [Node.js 18+](https://nodejs.org/) and npm
- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Docker](https://www.docker.com/get-started) (for local development and deployment)
- An Azure subscription with permissions to create resources

## Deploy to Azure

### 1. Clone the Repository

```bash
git clone <repository-url>
cd travel-planner-python-aca
```

### 2. Login to Azure

```bash
azd auth login
az login
```

### 3. Choose a Region

When selecting a region for deployment, ensure it supports the GPT-4.1 model:

```bash
az cognitiveservices usage list --location "eastus2" | \
  jq -r '.[] | select(.name.value | contains("OpenAI.Standard.gpt-4.1"))
             | select(.currentValue < .limit)
             | .name.value'
```

### 4. Set Model Location (if different from primary region)

```bash
export MODEL_LOCATION="westus3"
```

### 5. Provision and Deploy

```bash
azd up
```

This command will:
- Create a new resource group
- Provision Azure Container Registry, Container Apps, OpenAI, Durable Task Scheduler, and Storage
- Build and push Docker images
- Deploy the backend API and frontend applications

### 6. Access the Application

Once deployment completes, the CLI will output the URLs:

- **Frontend**: `https://<your-frontend-app>.<region>.azurecontainerapps.io`
- **API**: `https://<your-api-app>.<region>.azurecontainerapps.io`

## Local Development

### 1. Start Durable Task Scheduler Emulator

```bash
docker run -d -p 8080:8080 mcr.microsoft.com/dts/dts-emulator:latest
```

### 2. Start Azure Storage Emulator

```bash
npm install -g azurite
azurite --silent --location ./azurite &
```

### 3. Configure Local Settings

Copy `.env.template` to `.env` and update with your Azure OpenAI credentials:

```bash
cp .env.template .env
# Edit .env with your settings
```

### 4. Install Python Dependencies

```bash
cd api
pip install -r requirements.txt
```

### 5. Start the Backend

```bash
cd api
uvicorn app:app --reload --port 8000
```

### 6. Start the Frontend

```bash
cd frontend
npm install
npm start
```

The application will be available at `http://localhost:3000`.

## Testing the Application

1. Navigate to your frontend URL
2. Enter your travel preferences:
   - Destination preferences
   - Travel dates
   - Budget range
   - Activities of interest
3. Submit and watch the agents work
4. Review the generated travel plan
5. Approve or request changes

## Monitoring

### Durable Task Dashboard

Monitor your workflows at: `https://dashboard.durabletask.io/`

Configure with your subscription ID, resource group, and scheduler name.

### Container Apps Logs

```bash
az containerapp logs show \
  --name <container-app-name> \
  --resource-group <resource-group> \
  --follow
```

## Clean Up

To remove all Azure resources:

```bash
azd down --purge
```

## Project Structure

```
/
├── api/                          # Backend Python API
│   ├── app.py                    # FastAPI application
│   ├── agents/                   # AI agent implementations
│   │   ├── destination_agent.py
│   │   ├── itinerary_agent.py
│   │   └── local_guide_agent.py
│   ├── workflows/                # Durable task workflows
│   │   └── travel_workflow.py
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/                     # React frontend
│   ├── src/
│   ├── public/
│   ├── Dockerfile
│   └── nginx.conf
├── infra/                        # Bicep infrastructure
│   ├── main.bicep
│   ├── main.bicepparam
│   └── modules/
├── azure.yaml                    # Azure Developer CLI config
└── README.md
```

## Learn More

- [Durable Task Extension for Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [Azure Durable Task Scheduler](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-task-scheduler/)
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.
