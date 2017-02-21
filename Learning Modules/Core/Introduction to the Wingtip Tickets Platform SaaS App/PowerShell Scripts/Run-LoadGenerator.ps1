<#
.SYNOPSIS
This script is used to create a CPU based load against the Wingtip Tickets Platform Azure SQL Elastic Database Pool

.DESCRIPTION
This script is used to create a CPU based load against the Wingtip Tickets Platform Azure SQL Elastic Database Pool.
This script can also create a load against a singleton Azure SQL Database.

To run this script dot source load it into the PowerShell script.

. .\Run-LoadGenerator.ps1

.PARAMETER CatalogServer
This is the name of the Customer Catalog Azure SQL Server

.PARAMETER CatalogDatabase
This is the name of the Customer Catalog Database

.PARAMETER TenantResourceGroupName
This is the name of the Resource Group where the resources reside

.PARAMETER Intensity
This is the DTU Load intensity value

.PARAMETER DurationMinutes
This is the duration in minutes to run the load against the database

.PARAMETER SingleTenantDtu
This is the Single Tenant DTU load

.PARAMETER SingleTenantDatabaseName
This is the single Tenant Database Name

.EXAMPLE

Run-LoadGenerator -CatalogServer catalog -CatalogDatabase customercatalog -TenantResourceGroupName WingtipSaaS

#>

function Run-LoadGenerator{
    Param
    (
        [Parameter(Mandatory=$true)]
        [string]
        $CatalogServer,

        [Parameter(Mandatory=$true)]
        [string]
        $CatalogDatabase,
        
        [Parameter(Mandatory=$true)]
        [string]
        $TenantResourceGroupName,

        [Parameter(Mandatory=$false)]
        [string]
        $Intensity = 40,

        # Duration of the load generation session in minutes. Some activity may continue after this time. 
        [Parameter(Mandatory=$false)]
        [string]
        $DurationMinutes = 20,

        # If SingleTenant is enabled, specifies the load in DTU applied to an isolated tenant, defaults to 95 if not specified 
        [Parameter(Mandatory=$false)]
        [string]
        $SingleTenantDtu = 95,

        # If singleTenant is enabled, specifies the tenant database.  If not specified, a random tenant database is chosen
        [Parameter(Mandatory=$false)]
        [string]
        $SingleTenantDatabaseName
    )

    InitSubscription

    $adminUserName = "developer"
    $adminPassword = "P@ssword1"
    ## Configuration

    # Bursts are randomized, the following set the min and max duration in seconds
    $burstMinDuration = 30 
    $burstMaxDuration = 40

    # interval between bursts is randomized, the following set min and max interval in seconds
    $intervalMin = 100
    $intervalMax = 360

    # DTU burst level is randomized by applying a factor with min and max values 
    $burstMinFactor = 0.6
    $burstMaxFactor = 1.1

    # Load factor skews the load on databases for unbalanced pools or intense single tenant usage scenarios.  
    # Load factor impacts DTU levels and interval between bursts -> interval = interval/loadFactor (low load factor ==> longer intervals)
    $highPoolLoadFactor = 1.20
    $lowPoolLoadFactor = 0.50 
    # Load factor for single tenant burst mode
    $intenseLoadFactor = 15.00

    # density load factor, decreases the database load for pools with more dbs 
    # impacts interval between bursts interval = interval + (interval * dbCountLoadFactor * pool.dbcount)
    # 0 removes the effect, 0.1 will double the interval for 10 dbs  
    $densityLoadFactor = 0.06

     # Azure SQL DB server suffix 
    $serverSuffix = ".database.windows.net"

         # Get the set of servers from the catalog
        $query = `
        "SELECT DISTINCT ServerName 
            FROM __ShardManagement.ShardsGlobal AS S
            INNER JOIN __ShardManagement.ShardMapsGlobal AS SM ON SM.ShardMapId = S.ShardMapId
        WHERE SM.Name = 'CustomerCatalog'" 

        $server = $CatalogServer + $serverSuffix
        try
        {
            $FQServers = Invoke-Sqlcmd -ServerInstance $server -Database $CatalogDatabase -Username $adminUserName -Password $adminPassword -Query $query -QueryTimeout 300 
        }
        catch [Exception]
        {
            Write-Output $_.Exception.Message
            Write-Output ("Error connecting to catalog database " + $CatalogDatabase + "/" + $server)
        }

        [String[]]$ServerNames = @()

        foreach ($FQSrv in $FQServers)
        {
            $serverNames += ($FQSrv.ServerName).split(".",2)[0]
        }


        # Array that will contain all databases to be loaded
        $allDbs = @() 

        foreach($serverName in $serverNames)
        {
            [array]$serverPools = (Get-AzureRmSqlElasticPool -ResourceGroupName $TenantResourceGroupName -ServerName $serverName).ElasticPoolName
            $poolNumber = 1

            foreach($elasticPool in $serverPools)
            {
                # Set up the relative load level for each pool
                if($Unbalanced.IsPresent -and $serverPools.Count -gt 1)
                {
                    if ($poolNumber % 2 -ne 0)
                    {
                        $loadFactor = $highPoolLoadFactor
                        Write-Output ("Pool " + $elasticPool + " on " + $serverName + " has high load factor - " + $loadFactor)         
                    }
                    else
                    {
                        $loadFactor = $lowPoolLoadFactor 
                        Write-Output ("Pool "+ $elasticPool + " on " + $serverName + " has low load factor - " + $loadFactor)        
                    }
                }
                else
                {
                    # Neutral default for the relative load level for databases in a pool
                    $loadFactor = 1.0
                }
               
                $elasticDbs = (Get-AzureRmSqlElasticPoolDatabase -ResourceGroupName $TenantResourceGroupName -ServerName $serverName -ElasticPoolName $elasticPool).DatabaseName

                Foreach($elasticDb in $elasticDbs)
                {          
                    # vary the baseline DTU level of each database using a random factor x the input intensity x load factor for the pool 

                    $burstFactor = Get-Random -Minimum $burstMinFactor -Maximum $burstMaxFactor # randomizes the intensity of each database
                    $burstDtu = [math]::Ceiling($Intensity * $BurstFactor * $loadFactor)


                    # add db with its pool-based load factor
                    $dbProperties = @{ServerName=($serverName + ".database.windows.net");DatabaseName=$elasticDb;BurstDtu=$burstDtu;LoadFactor=$loadFactor;ElasticPoolName=$elasticPool;PoolDbCount=$elasticDbs.Count}
                    $db = New-Object PSObject -Property $dbProperties

                    $allDbs += $db       
                }
        
                $poolNumber ++        
            }

            Write-Output ""

            # Get standalone dbs and add to $allDbs

            $StandaloneDbs = (Get-AzureRmSqlDatabase -ResourceGroupName $TenantResourceGroupName -ServerName $serverName |  where {$_.CurrentServiceObjectiveName -ne "ElasticPool"} | where {$_.DatabaseName -ne "master"} ).DatabaseName 
            Foreach ($standaloneDb in $StandaloneDbs)
            {
                    $burstLevel = Get-Random -Minimum $burstMinFactor -Maximum $burstMaxFactor # randomizes the intensity of each database
                    $burstDtu = [math]::Ceiling($burstLevel * $Intensity)

                    #store db with a neutral load factor
                    $dbProperties = @{ServerName=($serverName + ".database.windows.net");DatabaseName=$StandaloneDb;BurstDtu=$burstDtu;LoadFactor=1.0;ElasticPoolName="";PoolDbCount=0.0}
                    $db = New-Object PSObject -Property $dbProperties

                    $allDbs += $db
            }    
        }
    # spawn jobs to spin up load on each database in $allDbs
    # note there are limits to using PS jobs at scale; this should only be used for small scale demonstrations 
   
        # Set the end time for all jobs
        $endTime = [DateTime]::Now.AddMinutes($DurationMinutes)
        # Script block for job that executes the load generation stored procedure on each database 
        $command = `
        {
            Write-Output ("Database " + $dbName + "/" + $server + " Load factor: " + $loadFactor + " Density weighting: " + ($densityLoadFactor*$poolDbCount)) 

            $endTime = [DateTime]::Now.AddMinutes($DurationMinutes)

            $firstTime = $true

            While ([DateTime]::Now -lt $endTime)
            {
                # add variable delay before execution, this staggers bursts
                # load factor is applied to reduce interval for high or intense loads, and increase interval for low loads
                # density load factor extends interval for higher density pools to reduce overloading
                if($firstTime)
                {
                    $snooze = [math]::ceiling((Get-Random -Minimum 0 -Maximum ($intervalMax - $intervalMin)) / $loadFactor)
                    $snooze = $snooze + ($snooze * $densityLoadFactor * $poolDbCount)
                    $firstTime = $false
                }
                else
                {
                    $snooze = [math]::ceiling((Get-Random -Minimum $intervalMin -Maximum $intervalMax) / $loadFactor)
                    $snooze = $snooze + ($snooze * $densityLoadFactor * $poolDbCount)
                }
                Write-Output ("Snoozing for " + $snooze + " seconds")  
                Start-Sleep $snooze

                # vary each burst to add realism to the workload
            
                # vary burst duration
                $burstDuration = Get-Random -Minimum $burstMinDuration -Maximum $burstMaxDuration

                # vary DTU 
                $dtuVariance = Get-Random -Minimum 0.9 -Maximum 1.1
                $burstDtu = [Math]::ceiling($baseDtu * $dtuVariance)

                # ensure burst DTU doesn't exceed 100 
                if($burstDtu -gt 100) 
                {
                    $burstDtu = 100
                }

                # configure and submit the SQL script to run the load generator
                $sqlScript = "EXEC sp_CpuLoadGenerator @duration_seconds = " + $burstDuration + ", @dtu_to_simulate = " + $burstDtu               
                try
                {
                    Invoke-Sqlcmd -ServerInstance $server -Database $dbName -Username $TenantUser -Password $TenantPassword -Query $sqlscript -QueryTimeout 36000         
                }
                catch
                {
                    Write-Output ("Error connecting to tenant database " + $dbName + "/" + $server)
                }

                [string]$message = $([DateTime]::Now) 
                Write-Output ( $message + " Starting load: " + $burstDtu + " DTUs for " + $burstDuration + " seconds")  

                # exit loop if end time exceeded
                if ([DateTime]::Now -gt $endTime)
                {
                    break;
                }
            }
        }
        # Start a job for each database.  Each job runs for the specified session duration and triggers load periodically.
        # The base-line load level for each db is set by the entry in $allDbs.  Burst duration, interval and DTU are randomized
        # slightly within each job to create a more realistic workload

        $randomTenantIndex = 0

        if ($SingleTenant.IsPresent)
        {
            if ($SingleTenantDatabaseName -eq "")
            {
                $randomTenantIndex = Get-Random -Minimum 1 -Maximum ($allDbs.Count + 1)        
            }
        }
        $i = 1

        foreach ($db in $allDBs)
        {
            # Customize the load applied for each database
            if ($SingleTenant)
            {
                if ($i -eq $randomTenantIndex) 
                {
                    # this is the randomly selected database, so use the single-tenant factors
                    $burstDtu = $SingleTenantDtu
                    $loadFactor = $intenseLoadFactor 
                }        
                elseif ($randomTenantIndex -eq 0 -and $SingleTenantDatabaseName -eq $db.DatabaseName) 
                {
                    # this is the named database, so use the single-tenant factors
                    $burstDtu = $SingleTenantDtu
                    $loadFactor = $intenseLoadFactor 
                }
                else 
                {             
                    # use per-db computed factors 
                    $burstDtu = $db.BurstDtu
                    $loadFactor = $db.LoadFactor
                }
            }
            else 
            {
                # use per-db computed factors
                $burstDtu = $db.BurstDtu
                $loadFactor = $db.LoadFactor
            }

            $poolDbCount = $db.PoolDbCount

            $i ++
    
            $fqServer= $db.ServerName + $serverSuffix

            $outputText = " Starting load on " + $db.DatabaseName + "/" + $db.ServerName + "with load factor " + $loadFactor + " Baseline DTU " + $burstDtu
            if ($db.ElasticPoolName -ne "")
            {
                $outputText += " in pool " + $db.ElasticPoolName
            }
            else
            {
                $outputText += " standalone"
            }

    
            $job = Start-Job -ScriptBlock $command -ArgumentList $(`
                $db.ServerName,$db.DatabaseName,$TenantUser,$TenantPassword,$DurationMinutes,$intervalMin,$intervalMax,$burstMinDuration,$burstMaxDuration,$burstDtu,$loadFactor,$densityLoadFactor,$poolDbCount)    

            $outputText = ("Job " + $job.Id + $outputText)
            write-output $outputText
        }
 }

function InitSubscription()
{
    $global:subscriptionID = ""
    try
        {
            $account = (Get-AzureRmContext -ErrorAction SilentlyContinue).Account
	        Write-Host "Azure Account"
            Write-Host "You are signed-in with $account"
	    }
    catch
        {
            $account  = Login-AzureRmAccount -WarningAction SilentlyContinue | out-null
        }
    if($global:subscriptionID -eq $null -or $global:subscriptionID -eq '')
        {
            $subList = Get-AzureRMSubscription

            if($subList.Length -lt 1)
                {
                    throw 'Your azure account does not have any subscriptions.  A subscription is required to run this tool'
                } 

            $subCount = 0
            foreach($sub in $subList)
                {
                    $subCount++
                    $sub | Add-Member -type NoteProperty -name RowNumber -value $subCount
                }

        Write-Host "Your Azure Subscriptions"
        $subList | Format-Table RowNumber,SubscriptionId,SubscriptionName -AutoSize
        Write-Host "Enter the row number (1 - $subCount) of a subscription"
        $rowNum = Read-Host 

        while( ([int]$rowNum -lt 1) -or ([int]$rowNum -gt [int]$subCount))
            {
                Write-Host "Invalid subscription row number. Please enter a row number from the list above"
                $rowNum = Read-Host 'Enter subscription row number'                     
            }
        $global:subscriptionID = $subList[$rowNum-1].SubscriptionId;
        $global:subscriptionName = $subList[$rowNum-1].SubscriptionName;
        }
    #switch to appropriate subscription
    try
        {
            Write-host "Selecting Subscription"
            $null = Select-AzureRMSubscription -SubscriptionId $global:subscriptionID
            Write-Host $global:subscriptionName
            
        } 
    catch 
        {
            throw 'Subscription ID provided is invalid: ' + $global:subscriptionID 
        }
}