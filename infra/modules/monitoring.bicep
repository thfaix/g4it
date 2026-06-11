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

@description('Email for the daily error-digest alert. Empty disables the alert (and its action group).')
param alertEmail string = ''

var errorDigestEnabled = !empty(alertEmail)

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

// Daily error-digest alert (opt-in via alertEmail). A scheduled log-query rule counts
// ERROR/Exception/SEVERE lines per Container App over the last 24h and emails the breakdown.
// The internal --INTERNAL-G4IT-- pseudo-org's benign KV miss is excluded so it doesn't spam.
resource errorActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (errorDigestEnabled) {
  name: '${namePrefix}-errors-ag'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'g4iterr'
    enabled: true
    emailReceivers: [
      {
        name: 'errorDigestEmail'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource errorDigestRule 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = if (errorDigestEnabled) {
  name: '${namePrefix}-error-digest'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'G4IT daily error digest'
    description: 'Daily count of ERROR/Exception/SEVERE log lines per Container App (benign --INTERNAL-G4IT-- KV miss excluded).'
    severity: 3
    enabled: true
    scopes: [ workspace.id ]
    evaluationFrequency: 'P1D'
    windowSize: 'P1D'
    criteria: {
      allOf: [
        {
          query: '''ContainerAppConsoleLogs_CL
| where Log_s has "ERROR" or Log_s has "Exception" or Log_s has "SEVERE"
| where Log_s !has "--INTERNAL-G4IT--"
| summarize ErrorCount = count() by ContainerAppName_s'''
          timeAggregation: 'Total'
          metricMeasureColumn: 'ErrorCount'
          dimensions: [
            {
              name: 'ContainerAppName_s'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: false
    actions: {
      actionGroups: [ errorActionGroup.id ]
    }
  }
}

output workspaceName string = workspace.name
output workspaceId string = workspace.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
