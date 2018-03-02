# Recover a multi-tenant SaaS application using geo-restore from database backups

In this tutorial, you explore a full disaster recovery scenario for a multi-tenant SaaS application implemented using the database-per-tenant model. You use [_geo-restore_](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-recovery-using-backups) to recover the catalog and tenant databases from automatically maintained geo-redundant backups into an alternate recovery region. After the outage, you use [_geo-replication_](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-geo-replication-overview) to repatriate changed databases to their original production region.

Geo-restore is the lowest-cost disaster recovery solution.  However, restoring from geo-redundant backups can result in data loss and can take a considerable time, depending on the size of the database. **To recover applications with the lowest possible RPO and RTO, use geo-replication instead of geo-restore**.

To reduce overall recovery time when restoring large numbers of databases, restore database in parallel into all pools. To repatriate databases once the outage is resolved, use geo-replication, which incurs no data loss and minimizes disruption. Repatriation of large numbers of databases also needs careful orchestration.


This tutorial explores both restore and repatriation workflows. You'll learn how to:

* Sync database and elastic pool configuration info into the tenant catalog
* Set up a mirror image recovery environment in a 'recovery' region, comprising application, servers, and pools    
* Recover catalog and tenant databases using _geo-restore_
* Repatriate the tenant catalog and changed tenant databases using _geo-replication_ after the outage is resolved
* Use database _aliases_ so that changes to connection strings are not required when recovering or repatriating databases 
 

Before starting this tutorial, make sure the following prerequisites are completed:
* The Wingtip Tickets SaaS database per tenant app is deployed. To deploy in less than five minutes, see [Deploy and explore the Wingtip Tickets SaaS database per tenant application](saas-dbpertenant-get-started-deploy.md)
* Azure PowerShell is installed. For details, see [Getting started with Azure PowerShell](https://docs.microsoft.com/powershell/azure/get-started-azureps)

## Introduction to the geo-restore recovery pattern

Disaster recovery (DR) is an important consideration for many applications, whether for compliance reasons or business continuity.  Should there be a prolonged service outage, a well-prepared DR plan will let you continue your business with the least possible disruption.

![Recovery Architecture](TutorialMedia/recoveryarchitecture.png)
 
For a SaaS application implemented with a database-per-tenant model, recovery and repatriation must be carefully orchestrated.

In this tutorial, you first recover the Wingtip Tickets application and its databases to a different region. Catalog and tenant databases are restored from geo-redundant copies of backups. When complete, the application is fully functional in the recovery region.

Later, in a separate repatriation step, you use geo-replication to copy the catalog and tenant databases changed after recovery to the original region. The application and databases stay online and available throughout.  When complete, the application is fully functional in the original region.

In a final step, you clean up the resources created in the recovery region.  

> Note that the application is recovered into the _paired region_ of the region in which the application is deployed. For more information, see [Azure paired regions](https://docs.microsoft.com/en-us/azure/best-practices-availability-paired-regions).   

Recovering a SaaS app with its many components needs careful orchestration. You need to: 
* Provision servers and pools in the recovery region to reserve capacity for existing tenants and allow new tenants to be provisioned  
* Deploy the app in the recovery region and configure it to provision new tenants as soon as possible
* Restore tenant databases across all elastic pools in parallel to ensure maximum throughput
* Submit restore requests asynchronously - the service maintains a queue for each pool and processes requests in batches to prevent overloading the system  
* Submit restore requests in batches to avoid service throttling limits
* Reactivate tenants as each database is restored 
* Restore tenants in priority order to minimize impact on key customers 
* Enable the app to connect to recovered databases without changing connection strings
* Allow the restore process to be canceled in mid-flight.  Canceling requires you revert all databases not yet recovered, or recovered but not yet updated, to the copy in the original region.  Reverting to the original database prevents data loss and reduces the number of databases that need repatriation
* Repatriate recovered databases that have been modified to the original production region.  Repatriation should have no impact on tenants 
* Ensure throughout the process that the app and tenant database are always colocated to minimize latency. 

In this tutorial, these challenges are addressed using features of Azure SQL Database and the Azure platform:

* Resource Management templates, to provision a mirror image of the production servers and elastic pools in the recovery region, and create a separate server and pool for provisioning new tenants. 
* [Geo-restore](https://docs.microsoft.com/azure/sql-database/sql-database-disaster-recovery), to recover the catalog and tenant databases from automatically maintained geo-redundant backups. 
* DNS aliases, to allow connecting to recovered and repatriated databases without changing or reconfiguring the app. Switching the active database requires only changing its alias.    
* Asynchronously submitted restore requests, to allow SQL Database to queue requests for each pool, and process them in batches to prevent overloading the pool.
* _Geo-replication_, to repatriate databases to the original region after the outage. Using geo-replication ensures there is no data loss and minimal impact on the tenant.    

## Get the disaster recovery management scripts 

The recovery scripts used in this tutorial are available in the [Wingtip Tickets SaaS database per tenant GitHub repository](https://github.com/Microsoft/WingtipTicketsSaaS-DbPerTenant/tree/feature-DR-georestore). Check out the [general guidance](saas-tenancy-wingtip-app-guidance-tips.md) for steps to download and unblock the Wingtip Tickets management scripts.

## Review the healthy state of the application
Before you start the recovery process, review the healthy start state of the application.
1. In your web browser, open the Wingtip Tickets Events Hub (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net - substitute &lt;user&gt; with your deployment's user value).
	* Notice the catalog server name in the footer
1. Click on the Contoso Concert Hall tenant and open its event page.
	* Notice the tenants server name in the footer
1. In the [Azure portal](https://portal.azure.com), open the resource group in which the app is deployed
	* Notice the region the servers are deployed in. 

## Sync tenant configuration into catalog

In this step, you sync the configuration of the servers, elastic pools, and databases into the tenant catalog.  This information is used later to configure a mirror image environment in the recovery region.

> Note: the sync process is implemented as a local Powershell job. In a production scenario, this process should be implemented as a reliable service of some kind.

1. In the _PowerShell ISE_, open the ...\Learning Modules\UserConfig.psm1 file. Replace `<resourcegroup>` and `<user>` on lines 10 and 11  with the value used when you deployed the app.  Save the file!

2. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 1, Start a background job that syncs tenant server, and pool configuration info into the catalog**

3. Press **F5** to run the sync script. A new PowerShell session is opened to sync the configuration of tenant resources.
![Sync process](TutorialMedia/syncprocess.png)

Leave the PowerShell window running in the background and continue with the rest of the tutorial. 

> Once the aliases are updated, the catalog sync process will automatically target the recovery versions of these databases.  Any configuration changes made to pools or databases after recovery are propagated to the production region as part of repatriation. 

## Restore tenant resources into the recovery region

This first phase reserves the required capacity up front, recovers tenant resources as fast as possible, and resumes onboarding tenants with the least interruption. This phase comprises the following steps:

1. Disable the Traffic Manager endpoint for the web app in the original production region. Disabling the endpoint prevents users from connecting to the app in an invalid state should the region come online during recovery.

1. Provision a recovery catalog server in the recovery region and then geo-restore the catalog database using an Azure Resource Manager template. Update the catalog alias to point to the recovery catalog database.

1. Mark all existing tenants in the recovery catalog as offline to prevent access to tenant databases before they are restored.

1. Provision an instance of the app in the recovery region plus a server and elastic pool to be used for provisioning new tenants. 
	* To keep app-to-database latency to a minimum, the sample app is designed so that it only connects to a tenant database in the same region.  If the app in one region detects that the active copy of a tenant database is in another region, it will redirect to an instance of the app in the other region. This is important during repatriation.
		
1. Provision the recovery server and pool resources required for restoring the existing tenant databases using an Azure Resource Manager template. Provisioning pools first reserves the capacity that will be needed for database recovery.
	* In there is a prolonged outage in a region, there may be significant pressure on the resources available in the paired region.  Reserving resources quickly is recommended. Use geo-replication if it is critical that the application must be recovered in a specific region. 

1. Enable the Traffic Manager endpoint for the web app in the recovery region.  At this stage, the application is able to support provisioning new tenants.   

1. Once all elastic pools are provisioned, submit batches of requests to restore databases across all pools in priority order. Batches are organized so that databases are restored in parallel across all pools.  
	* Restore requests are submitted asynchronously to allow requests to be submitted quickly and queued for execution.

1. Poll the database service to determine when databases are restored.  Once a tenant database is restored, update the corresponding tenant database alias to point to the recovered database instance.  And in the catalog, record the database rowversion and mark the tenant as online. 
	* Tenant databases can be accessed by the application as soon as they're marked online in the catalog. 
	* The database rowversion is recorded so that you can determine later if the database has been updated in the recovery region.. 

## Run the recovery script
Now run the recovery script which automates the restore steps described above:

1. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 2, Recover the SaaS app into a recovery region by restoring from geo-redundant backups**

2. Press **F5** to run the script.  The script starts a series of jobs that run in parallel which manage restore servers, pools and databases. The recovery region is the paired region associated with the region in which you deployed the application. For more information, see [Azure paired regions](https://docs.microsoft.com/en-us/azure/best-practices-availability-paired-regions). 

	Monitor the status of the recovery process in the console section of the PowerShell window.

**insert screenshot of powershell window with code running <<<**

>Explore the code for the recovery jobs that are running by reviewing the PowerShell scripts in the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\RecoveryJobs folder.

## Review the application state during recovery
While the tenant databases are being restored, the tenants are marked offline in the catalog.  Once the application has been deployed to the recovery region and activated, attempts to connect to individual tenants will fail until they are online.  Each tenant is brought back online as its database is restored.

1. Refresh the Wingtip Tickets Events Hub in your web browser (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net - substitute &lt;user&gt; with your deployment's user value). 
	* Notice that each tenant is marked as offline and that clicking on a tenant does not display that tenant's events. 

When the recovery process completes, the application is fully functional in the recovery region. 

## Review the recovered state of the application

With the application fully recovered, review how the application behaves.

1. In your web browser, refresh the Wingtip Tickets Events Hub  (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net - substitute &lt;user&gt; with your deployment's user value).
	* Notice the value reported for the catalog server in the footer is the catalog recovery server in the recovery region.

	![Recovered tenants list](TutorialMedia/recoveredcatalogserver.png)

	> ** UPDATE THIS IMAGE**

1. In the Events Hub, click on Contoso Concert Hall and open its events browse page, which is now available. Notice that the tenants recovery server referenced in the footer is the recovery server in the recovery region.

1. In the [Azure portal](https://portal.azure.com), inspect the recovery resource group.  Notice that the application and servers are deployed in the paired region of the ordinal deployment of the app.

## Change tenant data after restore to force database repatriation later
Before you run the repatriation script change data associated with one or two tenants.  Only tenant databases modified after restore are copied to the original region during the repatriation process. 

1. In the events list for the Contoso Concert Hall notices the last event name.
1. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 3** (Delete last event)
1. Press **F5** to execute the script
1. Refresh the Contoso Concert Hall events page (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net/contosoconcerthall - substitute &lt;user&gt; with your deployment's user value) and notice that the last event has been deleted.
1. Visit the Fabrikam Jazz Club events page and sign in and then purchase 10 tickets for the first event, _Exhibition Match_        

## Repatriate the application to its original production region

Repatriation reverts the application to the original production region after an outage. Repatriation should be triggered once you're satisfied the outage is resolved. Note that an outage may be resolved before the restore has completed. Starting repatriation cancels the prior restore activity.

Repatriation involves several distinct tasks:
1. Reactivate tenant databases in the original region that were not restored to the recovery region, or if restored, were never changed there. These databases will be exactly as last accessed by their tenants. These tenants will be immediately able to use the SaaS application.
1. Cause new tenant onboarding to occur in the original region so no more tenant databases are created in the recovery region
1. Cancel any outstanding or in-flight database restore requests.
1. Copy all restored databases _that have been changed post-restore_ to the original production region. This includes the catalog database and tenant databases.
1. Clean up resources created in the recovery region during the restore process.

It's important that steps 1-3 are done promptly.  

By contrast, it's important that step 4 causes no further disruption to tenants and no data loss. To achieve this goal, use _geo-replication_ to 'move' changed databases to the production region. If the app is working well in the recovery region, there may not be any great urgency to move databases back to the production region. 

Failing over each replicated database to the production region causes connections to be dropped briefly (usually in under five seconds).  Although this brief disconnect is often not noticed, you may choose to repatriate databases out of business hours. Once a database is failed over to its replica in the production region, the restored database in the recovery region can be deleted. The database in the production region then relies on geo-restore for DR protection again. 

In step 5, resources in the recovery region, including the recovery servers and pools, are deleted.    

The scope of repatriation varies depending on circumstances.  If new tenants were added in the recovery region during the outage, or any pool or database configuration was changed, then the catalog must be repatriated.  New tenant databases and restored tenant databases that have been updated post-restore must be repatriated. Databases that weren't restored, or were restored but unchanged, can be reactivated immediately in the original region - these databases won't have suffered any data loss.  

## Run the repatriation script
Now let's assume the outage is resolved and run the repatriation script.  This script reverts tenants you didn't modify to their original databases.  It then copies the databases you updated earlier to the production region, replacing the corresponding databases there.    
  
1. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 2, Recover the SaaS app into a recovery region by restoring from geo-redundant backups**

1. Press **F5** to run the recovery script. The repatriation of the changed databases will take several minutes.
1. While the script is running, refresh the Events Hub page (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net - substitute &lt;user&gt; with your deployment's user value)
	* Notice that all the tenants are online and accessible throughout this process.
1. Click on the Fabrikam Jazz Club and if you did not modify this tenant, notice the server is already reverted to the original production server.
1. Open or refresh the Contoso Concert Hall events page and notice from the footer that the database is on the _-recovery_ server initially.  
1. Refresh the Contoso Concert Hall events page when the repatriation process completes and notice that the server is now the original production server.
	* As each database fails over, connections to it are broken briefly and the database is inaccessible for a few seconds.

## Clean up recovery region resources after repatriation
Once repatriation completes, it's safe to delete the resources in the recovery region.  The restore process creates all the recovery resources in a recovery resource group.  Using a separate resource group allows them to be deleted together with a single action.
1. Open the [Azure portal](https://portal.azure.com) and delete the **ADD NAME OF RG HERE** resource group.
	* Deleting these resources promptly is recommended as it stops billing for them.



## Next steps

In this tutorial you learned how to:

* Sync tenant configuration data into the tenant catalog database
* Use tenant aliases to ensure no application changes are required during the recovery process 
* Restore Azure SQL servers, elastic pools, and Azure SQL databases into a recovery region
* Repatriate recovered databases that have been updated to the original production region

Now, try the [Recover a multi-tenant SaaS application using geo-replication]() to learn how to geo-replication can dramatically reduce the time needed to recover a large-scale multi-tenant application.

## Additional resources

* [Additional tutorials that build upon the Wingtip SaaS application](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-wtp-overview#sql-database-wingtip-saas-tutorials)
