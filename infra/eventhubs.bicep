// OPTIONAL shared Azure Event Hubs tier (Lab 05c).
// One instructor-run ingestion (NROD bridge + optional RDM relay) sends here; every student's
// Eventstream reads through its own consumer group. Event Hubs keeps buffering (up to 7 days on
// Standard) while a Fabric capacity is paused, and each Eventstream catches up when it resumes.
//
// Standard tier on purpose: Basic allows only 1 consumer group per event hub and 1-day retention.
// Standard: up to 20 consumer groups per event hub (including $Default), up to 7 days retention,
// 1 TU = 1 MB/s (or 1,000 events/s) in and 2 MB/s (or 4,096 events/s) out.
//
// Deployed by scripts/create-eventhub.sh / .ps1, which also writes the send connection strings
// into the shared Key Vault. Keys are never emitted as outputs.
targetScope = 'resourceGroup'

param location string = resourceGroup().location

@description('Prefix used for resource names. Keep it the same as NAME_PREFIX in the other labs.')
@minLength(3)
@maxLength(11)
param namePrefix string = 'railrti'

@description('Optional: explicit (globally unique) namespace name. Leave empty to generate one.')
param namespaceName string = ''

@description('Throughput units. 1 TU is plenty for TRUST + RTPPM (and TD) relays.')
@minValue(1)
@maxValue(40)
param throughputUnits int = 1

@description('Days to keep events. Standard tier maximum is 7.')
@minValue(1)
@maxValue(7)
param retentionDays int = 7

@description('Partitions per event hub (can\'t be changed later on Standard).')
@minValue(1)
@maxValue(32)
param partitionCount int = 2

@description('Event hub for the NROD STOMP bridge (envelope JSON -> student RawFeed tables).')
param nrodHubName string = 'nrod-feed'

@description('Event hub for the RDM Kafka relay (raw TRUST JSON -> student RdmTrustRaw tables).')
param rdmHubName string = 'rdm-trust'

@description('One consumer group per student Eventstream, created on BOTH hubs. Max 19 ($Default is reserved for the instructor; Standard allows 20 per hub).')
@maxLength(19)
param studentConsumerGroups array = []

param tags object = {
  project: 'rail-fabric-rti'
}

var suffix = uniqueString(resourceGroup().id, namePrefix)
var nsName = !empty(namespaceName) ? namespaceName : take('${namePrefix}-ehns-${suffix}', 50)

resource ns 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: nsName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: throughputUnits
  }
  properties: {
    isAutoInflateEnabled: false
    // Fabric Eventstream's Event Hubs source needs a publicly reachable namespace (or a managed private endpoint)
    // and shared access key authentication.
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    minimumTlsVersion: '1.2'
  }
}

// Students read with ONE namespace-level Listen key (Eventstream asks for key name + key).
// SAS rules can't be scoped to a consumer group, so rotate this key after each course.
resource studentsListen 'Microsoft.EventHub/namespaces/authorizationRules@2024-01-01' = {
  parent: ns
  name: 'students-listen'
  properties: {
    rights: [ 'Listen' ]
  }
}

resource nrodHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: ns
  name: nrodHubName
  properties: {
    partitionCount: partitionCount
    messageRetentionInDays: retentionDays
  }
}

resource nrodSend 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: nrodHub
  name: 'bridge-send'
  properties: {
    rights: [ 'Send' ]
  }
}

resource nrodConsumerGroups 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = [for cg in studentConsumerGroups: {
  parent: nrodHub
  name: cg
  properties: {
    userMetadata: 'rail-fabric-rti student Eventstream'
  }
}]

resource rdmHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: ns
  name: rdmHubName
  properties: {
    partitionCount: partitionCount
    messageRetentionInDays: retentionDays
  }
}

resource rdmSend 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: rdmHub
  name: 'bridge-send'
  properties: {
    rights: [ 'Send' ]
  }
}

resource rdmConsumerGroups 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2024-01-01' = [for cg in studentConsumerGroups: {
  parent: rdmHub
  name: cg
  properties: {
    userMetadata: 'rail-fabric-rti student Eventstream'
  }
}]

output namespaceName string = ns.name
output namespaceHost string = '${ns.name}.servicebus.windows.net'
output nrodHubName string = nrodHub.name
output rdmHubName string = rdmHub.name
output sendRuleName string = nrodSend.name
output listenRuleName string = studentsListen.name
output studentConsumerGroups array = studentConsumerGroups
