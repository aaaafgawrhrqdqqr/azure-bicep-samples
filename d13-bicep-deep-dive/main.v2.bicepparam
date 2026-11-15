using 'main.bicep'

param prefix = 'd13blog'
param environment = 'dev'
param deployLogs = true
param subnets = [
  { name: 'snet-app', prefix: '10.20.1.0/24' }
  { name: 'snet-data', prefix: '10.20.2.0/24' }
  { name: 'snet-mgmt', prefix: '10.20.3.0/24' }
]
