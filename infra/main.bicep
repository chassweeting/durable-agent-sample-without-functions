targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@description('Skip the creation of the virtual network and private endpoint')
param skipVnet bool = true

@description('Name of the API service')
param apiServiceName string = ''

@description('Name of the user assigned identity')
param apiUserAssignedIdentityName string = ''

@description('Name of the application insights resource')
param applicationInsightsName string = ''

@description('Name of the log analytics workspace')
param logAnalyticsName string = ''

@description('Name of the resource group')
param resourceGroupName string = ''

@description('Name of the storage account')
param storageAccountName string = ''

@description('Name of the virtual network')
param vNetName string = ''

@description('Disable local authentication for Azure Monitor')
param disableLocalAuth bool = true

@description('Name of the Durable Task Scheduler')
param dtsName string = ''

@description('Name of the task hub')
param taskHubName string = ''

@description('Durable Task Scheduler SKU name')
param dtsSkuName string = 'Consumption'

@description('Name of the web service')
param webServiceName string = ''

@description('Id of the user or app to assign application roles')
param principalId string = deployer().objectId

@description('Name of the Azure AI Services account')
param aiServicesName string = 'agentaiservices'

@description('Model name for deployment')
param modelName string = 'gpt-4.1'

@description('Model format for deployment')
param modelFormat string = 'OpenAI'

@description('Model version for deployment')
param modelVersion string = '2025-04-14'

@description('Model deployment SKU name')
param modelSkuName string = 'S0'

@description('Model deployment capacity')
param modelCapacity int = 10

@description('Model deployment location. If you want to deploy an Azure AI resource/model in different location than the rest of the resources created.')
param modelLocation string = location

@description('The AI Service Account full ARM Resource ID. This is an optional field, and if not provided, the resource will be created.')
param aiServiceAccountResourceId string = ''

@description('Name of the Container Registry')
param containerRegistryName string = ''

// Variables
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, rg.id, environmentName, location))
var aiResourceToken = toLower(uniqueString(subscription().id, rg.id, environmentName, modelLocation))
var tags = { 'azd-env-name': environmentName }

// Define the container app names first so we can construct the URLs
var apiAppName = !empty(apiServiceName) ? apiServiceName : '${abbrs.containerApp}-api-${resourceToken}'
var webAppName = !empty(webServiceName) ? webServiceName : '${abbrs.containerApp}-web-${resourceToken}'

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourceGroup}${environmentName}'
  location: location
  tags: tags
}

// User assigned managed identity using AVM
module apiUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  name: 'apiUserAssignedIdentity-${resourceToken}'
  scope: rg
  params: {
    name: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentity}api-${resourceToken}'
    location: location
    tags: tags
  }
}

// Backing storage using AVM
module storage 'br/public:avm/res/storage/storage-account:0.29.0' = {
  scope: rg
  name: 'storage-${resourceToken}'
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageAccount}${resourceToken}'
    location: location
    tags: tags
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    allowSharedKeyAccess: false
    blobServices: {
      containers: [
        { name: 'travel-plans' }
      ]
    }
    publicNetworkAccess: skipVnet ? 'Enabled' : 'Disabled'
    networkAcls: skipVnet ? {
        defaultAction: 'Allow'
        bypass: 'AzureServices'
      } : {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    roleAssignments: [
      {
        principalId: apiUserAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
        principalType: 'ServicePrincipal'
      }
      {
        principalId: apiUserAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
        principalType: 'ServicePrincipal'
      }
      {
        principalId: apiUserAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
        principalType: 'ServicePrincipal'
      }
      {
        principalId: apiUserAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
        principalType: 'ServicePrincipal'
      }
      {
        principalId: principalId
        roleDefinitionIdOrName: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner
        principalType: 'User'
      }
      {
        principalId: principalId
        roleDefinitionIdOrName: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
        principalType: 'User'
      }
      {
        principalId: principalId
        roleDefinitionIdOrName: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor
        principalType: 'User'
      }
      {
        principalId: principalId
        roleDefinitionIdOrName: '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor
        principalType: 'User'
      }
    ]
  }
}

// Container Registry using AVM
module containerRegistry 'br/public:avm/res/container-registry/registry:0.8.0' = {
  scope: rg
  name: 'containerRegistry-${resourceToken}'
  params: {
    name: !empty(containerRegistryName) ? containerRegistryName : '${abbrs.containerRegistry}${resourceToken}'
    location: location
    tags: tags
    acrSku: 'Basic'
    acrAdminUserEnabled: false
    roleAssignments: [
      {
        principalId: apiUserAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull
        principalType: 'ServicePrincipal'
      }
      {
        principalId: apiUserAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: '8311e382-0749-4cb8-b61a-304f252e45ec' // AcrPush (for azd deploy)
        principalType: 'ServicePrincipal'
      }
      {
        principalId: principalId
        roleDefinitionIdOrName: '8311e382-0749-4cb8-b61a-304f252e45ec' // AcrPush (for developer)
        principalType: 'User'
      }
    ]
  }
}

// Container Apps Environment using AVM
module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.8.1' = {
  scope: rg
  name: 'containerAppsEnv-${resourceToken}'
  params: {
    name: '${abbrs.containerAppsEnvironment}-${resourceToken}'
    location: location
    tags: tags
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.resourceId
    zoneRedundant: false
  }
}

// Backend API Container App using AVM
module apiContainerApp 'br/public:avm/res/app/container-app:0.12.0' = {
  scope: rg
  name: 'api-${resourceToken}'
  params: {
    name: apiAppName
    location: location
    tags: union(tags, { 'azd-service-name': 'api' })
    environmentResourceId: containerAppsEnvironment.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [apiUserAssignedIdentity.outputs.resourceId]
    }
    containers: [
      {
        name: 'api'
        image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        resources: {
          cpu: json('0.5')
          memory: '1Gi'
        }
        env: [
          { name: 'DURABLE_TASK_SCHEDULER_CONNECTION_STRING', value: 'Endpoint=${dts.outputs.dts_URL};Authentication=ManagedIdentity;ClientID=${apiUserAssignedIdentity.outputs.clientId}' }
          { name: 'TASKHUB_NAME', value: dts.outputs.TASKHUB_NAME }
          { name: 'AZURE_OPENAI_ENDPOINT', value: aiServiceExists ? reference(aiServiceAccountResourceId, '2023-05-01').endpoint : aiServices!.outputs.endpoint }
          { name: 'AZURE_OPENAI_DEPLOYMENT_NAME', value: modelName }
          { name: 'AZURE_CLIENT_ID', value: apiUserAssignedIdentity.outputs.clientId }
          { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: monitoring.outputs.connectionString }
        ]
      }
    ]
    registries: [
      {
        server: containerRegistry.outputs.loginServer
        identity: apiUserAssignedIdentity.outputs.resourceId
      }
    ]
    disableIngress: false
    ingressExternal: true
    ingressTargetPort: 8000
    ingressTransport: 'http'
    corsPolicy: {
      allowedOrigins: ['*']
      allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
      allowedHeaders: ['*']
    }
    scaleMinReplicas: 1
    scaleMaxReplicas: 10
  }
}

// Frontend Web Container App using AVM
module webContainerApp 'br/public:avm/res/app/container-app:0.12.0' = {
  scope: rg
  name: 'web-${resourceToken}'
  params: {
    name: webAppName
    location: location
    tags: union(tags, { 'azd-service-name': 'web' })
    environmentResourceId: containerAppsEnvironment.outputs.resourceId
    managedIdentities: {
      userAssignedResourceIds: [apiUserAssignedIdentity.outputs.resourceId]
    }
    containers: [
      {
        name: 'web'
        image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
        resources: {
          cpu: json('0.25')
          memory: '0.5Gi'
        }
        env: [
          { name: 'REACT_APP_API_URL', value: 'https://${apiContainerApp.outputs.fqdn}' }
        ]
      }
    ]
    registries: [
      {
        server: containerRegistry.outputs.loginServer
        identity: apiUserAssignedIdentity.outputs.resourceId
      }
    ]
    disableIngress: false
    ingressExternal: true
    ingressTargetPort: 80
    ingressTransport: 'http'
    scaleMinReplicas: 1
    scaleMaxReplicas: 3
  }
}

// AI Services configuration
var aiServiceExists = aiServiceAccountResourceId != ''
var aiServiceName = '${aiServicesName}${aiResourceToken}'

// AI Services (Cognitive Services) using AVM with model deployment
module aiServices 'br/public:avm/res/cognitive-services/account:0.9.2' = if (!aiServiceExists) {
  scope: rg
  name: 'aiServices-${aiResourceToken}'
  params: {
    name: aiServiceName
    location: modelLocation
    tags: tags
    kind: 'AIServices'
    customSubDomainName: toLower(aiServiceName)
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
    sku: modelSkuName
    deployments: [
      {
        name: modelName
        model: {
          format: modelFormat
          name: modelName
          version: modelVersion
        }
        sku: {
          name: 'GlobalStandard'
          capacity: modelCapacity
        }
      }
    ]
    roleAssignments: [
      {
        principalId: apiUserAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
        principalType: 'ServicePrincipal'
      }
      {
        principalId: principalId
        roleDefinitionIdOrName: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd' // Cognitive Services OpenAI User
        principalType: 'User'
      }
    ]
  }
}

// Storage role assignments using AVM pattern
var storageQueueDataContributorRole = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'

module storageQueueRoleApi 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: rg
  name: 'storageQueueApi-${resourceToken}'
  params: {
    principalId: apiUserAssignedIdentity.outputs.principalId
    roleDefinitionId: storageQueueDataContributorRole
    principalType: 'ServicePrincipal'
    resourceId: storage.outputs.resourceId
  }
}

module storageQueueRoleUser 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: rg
  name: 'storageQueueUser-${resourceToken}'
  params: {
    principalId: principalId
    roleDefinitionId: storageQueueDataContributorRole
    principalType: 'User'
    resourceId: storage.outputs.resourceId
  }
}

// Virtual Network using AVM
var vnetName = !empty(vNetName) ? vNetName : '${abbrs.virtualNetwork}${resourceToken}'

module serviceVirtualNetwork 'br/public:avm/res/network/virtual-network:0.7.1' = if (!skipVnet) {
  scope: rg
  name: 'vnet-${resourceToken}'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: ['10.0.0.0/16']
    subnets: [
      {
        name: 'app-subnet'
        addressPrefix: '10.0.0.0/24'
        delegation: 'Microsoft.App/environments'
      }
      {
        name: 'pe-subnet'
        addressPrefix: '10.0.1.0/24'
      }
    ]
  }
}

// Private DNS Zone for blob storage
module privateDnsZone 'br/public:avm/res/network/private-dns-zone:0.8.0' = if (!skipVnet) {
  scope: rg
  name: 'pdns-${resourceToken}'
  params: {
    name: 'privatelink.blob.${environment().suffixes.storage}'
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: serviceVirtualNetwork!.outputs.resourceId
      }
    ]
  }
}

// Private Endpoint for storage using AVM
module storagePrivateEndpoint 'br/public:avm/res/network/private-endpoint:0.11.1' = if (!skipVnet) {
  scope: rg
  name: 'pe-${resourceToken}'
  params: {
    name: 'pe-storage-${resourceToken}'
    location: location
    tags: tags
    subnetResourceId: '${serviceVirtualNetwork!.outputs.resourceId}/subnets/pe-subnet'
    privateLinkServiceConnections: [
      {
        name: 'storage-blob-connection'
        properties: {
          privateLinkServiceId: storage.outputs.resourceId
          groupIds: ['blob']
        }
      }
    ]
    privateDnsZoneGroup: {
      privateDnsZoneGroupConfigs: [
        {
          privateDnsZoneResourceId: privateDnsZone!.outputs.resourceId
        }
      ]
    }
  }
}

// Log Analytics Workspace using AVM
module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.13.0' = {
  scope: rg
  name: 'logs-${resourceToken}'
  params: {
    name: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.logAnalyticsWorkspace}${resourceToken}'
    location: location
    tags: tags
  }
}

// Application Insights using AVM
module monitoring 'br/public:avm/res/insights/component:0.7.1' = {
  scope: rg
  name: 'monitoring-${resourceToken}'
  params: {
    name: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.applicationInsights}${resourceToken}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: disableLocalAuth
    roleAssignments: [
      {
        principalId: apiUserAssignedIdentity.outputs.principalId
        roleDefinitionIdOrName: '3913510d-42f4-4e42-8a64-420c390055eb' // Monitoring Metrics Publisher
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

var durableTaskDataContributorRoleDefinitionId = '0ad04412-c4d5-4796-b79c-f76d14c8d402'

module dtsRoleApi 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: rg
  name: 'dtsRoleApi-${resourceToken}'
  params: {
    principalId: apiUserAssignedIdentity.outputs.principalId
    roleDefinitionId: durableTaskDataContributorRoleDefinitionId
    principalType: 'ServicePrincipal'
    resourceId: dts.outputs.dts_ID
  }
}

module dtsRoleUser 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.2' = {
  scope: rg
  name: 'dtsRoleUser-${resourceToken}'
  params: {
    principalId: principalId
    roleDefinitionId: durableTaskDataContributorRoleDefinitionId
    principalType: 'User'
    resourceId: dts.outputs.dts_ID
  }
}

// Durable Task Scheduler doesn't have AVM support yet
module dts './app/dts.bicep' = {
  scope: rg
  name: 'dtsResource-${resourceToken}'
  params: {
    name: !empty(dtsName) ? dtsName : '${abbrs.durableTaskScheduler}${resourceToken}'
    taskhubname: !empty(taskHubName) ? taskHubName : '${abbrs.taskHub}${resourceToken}'
    location: location
    tags: tags
    ipAllowlist: [
      '0.0.0.0/0'
    ]
    skuName: dtsSkuName
  }
}

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.connectionString
output AZURE_LOCATION string = location
output SERVICE_API_NAME string = apiContainerApp.outputs.name
output SERVICE_API_URI string = 'https://${apiContainerApp.outputs.fqdn}'
output CONTAINER_APP_API_NAME string = apiContainerApp.outputs.name
output CONTAINER_APP_WEB_NAME string = webContainerApp.outputs.name
output CONTAINER_APP_WEB_URI string = 'https://${webContainerApp.outputs.fqdn}'
output RESOURCE_GROUP string = rg.name
output STORAGE_CONNECTION__queueServiceUri string = 'https://${storage.outputs.name}.queue.${environment().suffixes.storage}'
output AZURE_OPENAI_ENDPOINT string = aiServiceExists ? reference(aiServiceAccountResourceId, '2023-05-01').endpoint : aiServices!.outputs.endpoint
output AZURE_OPENAI_DEPLOYMENT_NAME string = modelName
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.outputs.loginServer
