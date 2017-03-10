# Initializes a database with the Shard Management schema

Import-Module "$PSScriptRoot\..\Learning Modules\Common\AzureShardManagement" -Force

New-ShardMapManager `
    -SqlServerName "Wingtip-catalog-gold.database.windows.net" `
    -SqlDatabaseName "wingtipcatalogdb" `
    -UserName "developer" `
    -Password "P@ssword1"