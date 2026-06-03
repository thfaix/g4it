// ADR-001: Azure Container Apps managed environment, VNet-injected (ADR-009) and wired to
// the Log Analytics workspace (ADR-006). Uses the Consumption workload profile.

@description('Environment name.')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Name of the Log Analytics workspace (same resource group) used for app logs.')
param logAnalyticsWorkspaceName string

@description('Infrastructure subnet id (delegated to Microsoft.App/environments).')
param infrastructureSubnetId string

@description('Whether the environment uses an internal-only load balancer. Keep false so the public apps get external ingress.')
param internal bool = false

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: workspace.properties.customerId
        sharedKey: workspace.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: internal
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output id string = environment.id
output name string = environment.name
output defaultDomain string = environment.properties.defaultDomain
