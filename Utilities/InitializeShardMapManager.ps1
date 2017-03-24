# Initializes a database with the Shard Management schema

Import-Module "$PSScriptRoot\..\Learning Modules\Common\AzureShardManagement" -Force

New-ShardMapManager `
    -SqlServerName "<fully qualified server name>" `
    -SqlDatabaseName "<database name>" `
    -UserName "<user name>" `
    -Password "<password>"