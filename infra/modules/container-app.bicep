// Reusable single container app (ADR-001). Pulls from ACR and reads Key Vault secrets via
// the shared user-assigned managed identity (ADR-005, ADR-007). Set `external` to expose the
// app publicly (frontend/backend/keycloak) or keep internal ingress for the rest (ADR-009).

@description('Container app name (also the internal DNS name within the environment).')
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('ACA managed environment id.')
param environmentId string

@description('User-assigned managed identity id (ACR pull + Key Vault secret refs).')
param identityId string

@description('ACR login server, e.g. myregistry.azurecr.io.')
param acrLoginServer string

@description('Full image reference, e.g. myregistry.azurecr.io/g4it/backend:1.2.3.')
param image string

@description('Whether the app exposes HTTP ingress.')
param ingressEnabled bool = true

@description('External (public) ingress when true; internal-only when false.')
param external bool = false

@description('Container target port.')
param targetPort int = 8080

@description('CPU cores (string so fractional values like "0.5" are preserved).')
param cpu string = '0.5'

@description('Memory, e.g. "1Gi".')
param memory string = '1Gi'

param minReplicas int = 1
param maxReplicas int = 3

@description('Environment variables: [{ name, value } | { name, secretRef }].')
param env array = []

@description('Key Vault secret references: [{ name, keyVaultUrl }].')
param secrets array = []

@description('Workload profile name.')
param workloadProfileName string = 'Consumption'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    workloadProfileName: workloadProfileName
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: ingressEnabled ? {
        external: external
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
      } : null
      registries: [
        {
          server: acrLoginServer
          identity: identityId
        }
      ]
      secrets: [
        for s in secrets: {
          name: s.name
          keyVaultUrl: s.keyVaultUrl
          identity: identityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: name
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: env
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output fqdn string = ingressEnabled ? app.properties.configuration.ingress.fqdn : ''
output name string = app.name
