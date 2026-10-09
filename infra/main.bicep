// Real-Time Rail Intelligence - STOMP bridge hosting on Azure Container Apps.
// Two-phase deployment (see scripts/deploy-bridge.sh):
//   1. deployApp=false -> identity, Log Analytics, Key Vault, ACR, Container Apps environment
//   2. secrets are written to Key Vault and the image is built/pushed
//   3. deployApp=true  -> the single-replica container app that reads secrets from Key Vault
targetScope = 'resourceGroup'

@description('Azure region. Pick the region closest to your Fabric capacity (e.g. uksouth).')
param location string = resourceGroup().location

@description('Short prefix used in resource names (lowercase letters/numbers, 3-11 chars).')
@minLength(3)
@maxLength(11)
param namePrefix string = 'railrti'

@description('Deploy the container app (phase 2). Leave false on the first run.')
param deployApp bool = false

@description('Create an Azure Container Registry. Set false to use a public image (e.g. GHCR).')
param createAcr bool = true

@description('Full container image reference. Leave empty to use <acr>/rail-bridge:<imageTag>.')
param containerImage string = ''

@description('Image tag when using the ACR created by this template.')
param imageTag string = 'latest'

@description('vCPU for the bridge. 0.25 is enough for TRUST; consider 0.5 for TD_ALL_SIG_AREA.')
@allowed([ '0.25', '0.5', '0.75', '1.0' ])
param cpu string = '0.25'

@description('Memory for the bridge; must pair with cpu (0.25->0.5Gi, 0.5->1Gi, 0.75->1.5Gi, 1.0->2Gi).')
@allowed([ '0.5Gi', '1Gi', '1.5Gi', '2Gi' ])
param memory string = '0.5Gi'

@description('Comma-separated NROD topics.')
param nrodTopics string = 'TRAIN_MVT_ALL_TOC'

@description('Durable subscription name prefix (activemq.subscriptionName = <prefix>-<topic>).')
param subscriptionPrefix string = 'rail-fabric-rti'

@description('Object ID of the person/pipeline running the deployment; granted Key Vault Secrets Officer so it can write secrets.')
param deployerPrincipalId string = ''

@description('Principal type for deployerPrincipalId.')
@allowed([ 'User', 'ServicePrincipal', 'Group' ])
param deployerPrincipalType string = 'User'

@description('Log Analytics retention in days.')
param logRetentionDays int = 30

param tags object = {
  project: 'rail-fabric-rti'
}

@description('Optional: name of an existing Key Vault in this resource group (e.g. one you created by hand in Lab 01). Leave empty to use the generated name, which matches infra/keyvault.bicep.')
param keyVaultName string = ''

var suffix = uniqueString(resourceGroup().id, namePrefix)
var kvName = !empty(keyVaultName) ? keyVaultName : take('${namePrefix}kv${suffix}', 24)
var acrName = take('${namePrefix}acr${suffix}', 50)
var acrImage = createAcr ? '${acr.properties.loginServer}/rail-bridge:${imageTag}' : ''
var image = !empty(containerImage) ? containerImage : acrImage

// Built-in role definition IDs
var roleAcrPull = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var roleKvSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'
var roleKvSecretsOfficer = 'b86a8fe4-95b2-4a9a-9c4d-7de2ae5e7b32'

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-bridge-id'
  location: location
  tags: tags
}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

resource kvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, uami.id, roleKvSecretsUser)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleKvSecretsUser)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(kv.id, deployerPrincipalId, roleKvSecretsOfficer)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleKvSecretsOfficer)
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = if (createAcr) {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createAcr) {
  name: guid(acrName, uami.id, roleAcrPull)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleAcrPull)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-env'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = if (deployApp) {
  name: '${namePrefix}-bridge'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    environmentId: env.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      // No ingress: the bridge only makes outbound connections. Probes still reach the container.
      registries: createAcr ? [ { server: acr.properties.loginServer, identity: uami.id } ] : []
      secrets: [
        {
          name: 'nrod-username'
          keyVaultUrl: '${kv.properties.vaultUri}secrets/nrod-username'
          identity: uami.id
        }
        {
          name: 'nrod-password'
          keyVaultUrl: '${kv.properties.vaultUri}secrets/nrod-password'
          identity: uami.id
        }
        {
          name: 'eventstream-connection-string'
          keyVaultUrl: '${kv.properties.vaultUri}secrets/eventstream-connection-string'
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'bridge'
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: [
            { name: 'BRIDGE_SOURCE', value: 'stomp' }
            { name: 'BRIDGE_SINK', value: 'eventstream' }
            { name: 'NROD_TOPICS', value: nrodTopics }
            { name: 'NROD_SUBSCRIPTION_PREFIX', value: subscriptionPrefix }
            { name: 'NROD_DURABLE', value: 'true' }
            { name: 'NROD_HEARTBEAT_MS', value: '15000' }
            { name: 'HEALTH_PORT', value: '8080' }
            { name: 'LOG_LEVEL', value: 'INFO' }
            { name: 'NROD_USERNAME', secretRef: 'nrod-username' }
            { name: 'NROD_PASSWORD', secretRef: 'nrod-password' }
            { name: 'EVENTSTREAM_CONNECTION_STRING', secretRef: 'eventstream-connection-string' }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 30
              failureThreshold: 3
            }
            {
              type: 'Startup'
              httpGet: {
                path: '/healthz'
                port: 8080
              }
              initialDelaySeconds: 3
              periodSeconds: 5
              failureThreshold: 12
            }
          ]
        }
      ]
      // Exactly one replica: NROD allows one connection per durable client-id.
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
  dependsOn: [
    kvSecretsUser
    acrPull
  ]
}

output keyVaultName string = kv.name
output keyVaultUri string = kv.properties.vaultUri
output acrName string = createAcr ? acr.name : ''
output acrLoginServer string = createAcr ? acr.properties.loginServer : ''
output containerAppName string = deployApp ? app.name : ''
output environmentName string = env.name
output logAnalyticsWorkspaceName string = law.name
output identityPrincipalId string = uami.properties.principalId
