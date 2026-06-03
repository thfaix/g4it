// ADR-006: Observability — Log Analytics workspace + Application Insights.
// The Log Analytics workspace is the (required) log sink for the ACA environment;
// Application Insights collects backend telemetry/traces.

@description('Base name for the monitoring resources.')
param namePrefix string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Log retention in days.')
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${namePrefix}-appi'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
  }
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
