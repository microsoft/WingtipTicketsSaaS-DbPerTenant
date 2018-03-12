# Recover a multi-tenant SaaS application using geo-restore from database backups

In this tutorial, you explore a full disaster recovery scenario for a multi-tenant SaaS application implemented using the database-per-tenant model. You use [_geo-restore_](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-recovery-using-backups) to recover the catalog and tenant databases from automatically maintained geo-redundant backups into an alternate recovery region. After the outage is resolved, you use [_geo-replication_](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-geo-replication-overview) to repatriate changed databases to their original production region.

Geo-restore is the lowest-cost disaster recovery solution.  However, restoring from geo-redundant backups can result in data loss and can take a considerable time, depending on the size of the databases. **To recover applications with the lowest possible RPO and RTO, use geo-replication instead of geo-restore**.

This tutorial explores both restore and repatriation workflows. You'll learn how to:

* Sync database and elastic pool configuration info into the tenant catalog
* Set up a mirror image environment in a 'recovery' region, comprising application, servers, and pools    
* Recover catalog and tenant databases using _geo-restore_
* Repatriate the tenant catalog and changed tenant databases using _geo-replication_ after the outage is resolved
* Update the catalog as each database is restored (or repatriated) to track the current location of the active copy of each tenant's database
* Ensure the application and tenant database are always colocated in the same Azure region to reduce latency  
 

Before starting this tutorial, make sure the following prerequisites are completed:
* The Wingtip Tickets SaaS database per tenant app is deployed. To deploy in less than five minutes, see [Deploy and explore the Wingtip Tickets SaaS database per tenant application](saas-dbpertenant-get-started-deploy.md)  
* Azure PowerShell is installed. For details, see [Getting started with Azure PowerShell](https://docs.microsoft.com/powershell/azure/get-started-azureps)

## Introduction to the geo-restore recovery pattern

Disaster recovery (DR) is an important consideration for many applications, whether for compliance reasons or business continuity.  Should there be a prolonged service outage, a well-prepared DR plan can minimize business disruption.

![Recovery Architecture](TutorialMedia/recoveryarchitecture.png)
 
For a SaaS application implemented with a database-per-tenant model, recovery and repatriation must be carefully orchestrated.

In this tutorial, you first recover the Wingtip Tickets application and its databases to a different region. Catalog and tenant databases are restored from geo-redundant copies of backups. When complete, the application is fully functional in the recovery region.

Later, in a separate repatriation step, you use geo-replication to copy the catalog and tenant databases changed after recovery to the original region. The application and databases stay online and available throughout.  When complete, the application is fully functional in the original region.

In a final step, you clean up the resources created in the recovery region.  

> Note: the application is recovered into the _paired region_ of the region in which the application is deployed. For more information, see [Azure paired regions](https://docs.microsoft.com/en-us/azure/best-practices-availability-paired-regions).   

Recovering a SaaS app with its many components into another region needs careful orchestration. You need to: 
* Provision servers and pools in the recovery region to reserve capacity for new and existing tenants  
* Deploy the app in the recovery region and enable it to continue provisioning new tenants
* Restore tenant databases across all elastic pools in parallel to ensure maximum throughput
* Submit restore requests in batches to avoid service throttling limits
* Restore tenants in priority order to minimize impact on key customers 
* Submit restore requests asynchronously - the service maintains a queue of requests for each elastic pool to prevent the pool from being overloaded  
* Reactivate tenants in the catalog as each database is restored 
* Enable the app to connect to recovered databases without changing connection strings
* Allow the restore process to be canceled in mid-flight.  Canceling requires you revert all databases not yet recovered, or recovered but not yet updated, to the copy in the original region.  Reverting to the original database prevents data loss and reduces the number of databases that need repatriation
* Repatriate recovered databases that have been modified to the original region without data loss. 
* Ensure the app and tenant database are always colocated to minimize latency. 

In this tutorial, these challenges are addressed using features of Azure SQL Database and the Azure platform:

* Resource Management templates, to provision a mirror image of the production servers and elastic pools in the recovery region, and create a separate server and pool for provisioning new tenants. 
* [Geo-restore](https://docs.microsoft.com/azure/sql-database/sql-database-disaster-recovery), to recover the catalog and tenant databases from automatically maintained geo-redundant backups. 
* Shard management recovery features to change database entries in the catalog during recovery and repatriation.  These features allow the app to connect to tenant databases regardless of location without reconfiguring the app.    
* Asynchronously submitted restore requests that are queued for each pool by the system.  These requests are processed in batches so the pool is not overloaded.
* _Geo-replication_, to repatriate databases to the original region after the outage. Using geo-replication ensures there is no data loss and minimal impact on the tenant.    

## Get the disaster recovery management scripts 

The recovery scripts used in this tutorial are available in the [Wingtip Tickets SaaS database per tenant GitHub repository](https://github.com/Microsoft/WingtipTicketsSaaS-DbPerTenant/tree/feature-DR-georestore). Check out the [general guidance](saas-tenancy-wingtip-app-guidance-tips.md) for steps to download and unblock the Wingtip Tickets management scripts.

## Review the healthy state of the application
Before you start the recovery process, review the normal healthy state of the application.
1. In your web browser, open the Wingtip Tickets Events Hub (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net - substitute &lt;user&gt; with your deployment's user value).
	* Notice the catalog server name in the footer
1. Click on the Contoso Concert Hall tenant and open its event page.
	* Notice the tenants server name in the footer
1. In the [Azure portal](https://portal.azure.com), open the resource group in which the app is deployed
	* Notice the region in which the servers are deployed. 

## Sync tenant configuration into catalog

In this task, you start a process to sync the configuration of the servers, elastic pools, and databases into the tenant catalog.  The process keeps this information up-to-date in the catalog so it can be used later to configure a mirror image environment in the recovery region.

> Note: the sync process is implemented as a local Powershell job. In a production scenario, this process should be implemented as a reliable Azure service of some kind.

1. In the _PowerShell ISE_, open the ...\Learning Modules\UserConfig.psm1 file. Replace `<resourcegroup>` and `<user>` on lines 10 and 11  with the value used when you deployed the app.  Save the file!

2. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 1, Start a background job that syncs tenant server, and pool configuration info into the catalog**

3. Press **F5** to run the sync script. A new PowerShell session is opened to sync the configuration of tenant resources.
![Sync process](TutorialMedia/syncprocess.png)

Leave the PowerShell window running in the background and continue with the rest of the tutorial. 

> Note: The sync process connects to the catalog via a DNS alias. This alias is modified during restore and repatriation to point to the active catalog. The sync process keeps the catalog up to date with any configuration changes made in the recovery region.  During repatriation, these changes are applied to the equivalent resources in the original region. 

## Restore tenant resources into the recovery region

The restore process process does the following:

1. Disables the Traffic Manager endpoint for the web app in the original region. Disabling the endpoint prevents users from connecting to the app in an invalid state should the region come online during recovery.

1. Provisions a recovery catalog server in the recovery region and then geo-restores the catalog database and updates the catalog alias to point to the restored database.  
	* The catalog alias is used by the catalog sync process

1. Marks all existing tenants in the recovery catalog as offline to prevent access to tenant databases before they are restored.

1. Provisions an instance of the app in the recovery region and configures it to use the restored catalog in that region.

1. Provisions a server and elastic pool in which new tenants will be provisioned. 
	* To keep app-to-database latency to a minimum, the sample app is designed so that it always connects to a tenant database in the same region.
		
1. Provisions the recovery server and elastic pools required for restoring existing tenant databases. The configuration in the recovery region is a mirror image of the configuration in the original region.  An additional server and pool is provisioned for new tenants.  Provisioning pools up-front is important to reserve all the capacity needed.
	* An outage in one region may place significant pressure on the resources available in the paired region.  Reserving resources quickly is recommended. Consider using geo-replication if it is critical that an application must be recovered in a specific region. 

1. Enables the Traffic Manager endpoint for the Web app in the recovery region, which allows the application to provision new tenants.   

1. Submits batches of requests to restore databases across all pools in priority order. 
	* Batches are organized so that databases are restored in parallel across all pools.  
	* Restore requests are submitted asynchronously so they are submitted quickly and queued for execution.
	* As restore requests are processed in parallel across all pools, it is better to distribute important tenants across many pools rather than concentrating them in a few pools. 

1. Polls the database service to determine when databases are restored.  Once a tenant database is restored, it updates the catalog to record the database rowversion and mark the tenant as online. 
	* Tenant databases can be accessed by the application as soon as they're marked online in the catalog. 
	* Recording the rowversion allows the repatriation process to determine if the database has been updated in the recovery region.   	 

## Run the recovery script

> IMPORTANT This tutorial restores databases from geo-redundant backups. These backups may not be available for 10-20 minutes after initial database creation. Wait for 20 mins from installation of the app before running this script.

Now run the recovery script that automates the restore steps described previously:

1. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 2, Recover the app into a recovery region by restoring from geo-redundant backups**

1. Press **F5** to run the script.  
	* The script starts a series of PowerShell jobs that run in parallel which restore servers, pools, and databases to the recovery region. 
	* The recovery region is the _paired region_ associated with the Azure region in which you deployed the application. For more information, see [Azure paired regions](https://docs.microsoft.com/en-us/azure/best-practices-availability-paired-regions). 

1. Monitor the status of the recovery process in the console section of the PowerShell window.

**insert screenshot of powershell window with code running <<<**

>To explore the code for the recovery jobs, review the PowerShell scripts in the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\RecoveryJobs folder.

## Review the application state during recovery
Tenants are marked offline in the catalog while their databases are restoring.  Connections to tenant databases are unsuccessful until they are restored and marked online.  It's important to design your application to handle offline tenant databases.

1. Before the restore process completes, refresh the Wingtip Tickets Events Hub in your web browser (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net - substitute &lt;user&gt; with your deployment's user value).  
	* From the footer, notice that the catalog from the recovery server is used to source the list of tenants.
	* Notice that tenants that are not yet restored are marked as offline.  And if you click an offline tenant, its events page displays a 'tenant offline' notification. 

## Provision a new tenant in the recovery region
Even before the existing tenant databases are restored, you can provision new tenants in the recovery region. If you provision a new tenant database it will be repatriated with the existing databases later.

1. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following property:
	* **$DemoScenario = 3, Provision a new tenant in the recovery region**

1. Press **F5** to run the script and provision the new tenant. 

1. The Hawthorn Hall events page opens in the browser when it completes. Note from the footer that the Hawthorn Hall database is provisioned on the recovery tenants server.

1. In the browser, refresh the Wingtip Tickets Events Hub page. 
	* Note that while Hawthorn Hall is now provisioned and available, other tenants may still be offline.

## Review the recovered state of the application

When the recovery process completes, the application and all tenants are fully functional in the recovery region. 

Once the application is fully recovered, review how it behaves.

1. In your web browser, refresh the Wingtip Tickets Events Hub  (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net - substitute &lt;user&gt; with your deployment's user value).
	* Notice the value reported for the catalog server in the footer is the catalog recovery server in the recovery region.

	![Recovered tenants list](TutorialMedia/recoveredcatalogserver.png)

	> ** UPDATE THIS IMAGE**

1. In the Events Hub, click on Contoso Concert Hall and open its Events page, which is now available. Notice that the  server referenced in the footer is the recovery server in the recovery region.

1. In the [Azure portal](https://portal.azure.com), inspect the recovery resource group.  Notice that the application and recovery servers are in the paired region of the original app deployment.

## Change tenant data 
In this task, you update one of the restored tenant databases. The repatriation process will copy restored databases that have been changed to the original region. 

1. In your browser, find the events list for the Contoso Concert Hall and note the last event name.
1. In the *PowerShell ISE*, in the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script, set the following value:
	* **$DemoScenario = 3** (Delete last event)
1. Press **F5** to execute the script
1. Refresh the Contoso Concert Hall events page (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net/contosoconcerthall - substitute &lt;user&gt; with your deployment's user value) and notice that the last event has been deleted.

## Repatriate the application to its original production region

In this task, you repatriate the application to its original region.  In a real outage, repatriation is triggered once you're satisfied the outage is resolved. Note that starting repatriation cancels any ongoing restore activity.

The repatriation process:
1. Reactivates tenant databases in the original region that have not been restored to the recovery region and restored databases that have not been changed. These databases will be exactly as last accessed by their tenants and are immediately available to the application.
1. Causes new tenant onboarding to occur in the original region so no further tenant databases are created in the recovery region.
1. Cancels any outstanding or in-flight database restore requests.
1. Copies all restored databases _that have been changed post-restore_ to the original region.
1. Cleans up resources created in the recovery region during the restore process.

To limit the number of tenant databases that need to be repatriated, steps 1-3 are done promptly.  

It's important that step 4 causes no further disruption to tenants and no data loss. To achieve this goal, the process uses _geo-replication_ to 'move' changed databases to the original region.

Once each database being repatriated has been replicated to the original region, it is failed over.  Failover effectively moves the database to the original region. When the database fails over, any open connections are dropped and the database is unavailable for a few seconds. Applications should be written with retry logic to ensure they connect again.  Although this brief disconnect is often not noticed, you may choose to repatriate databases out of business hours. 

Once a database is failed over to its replica in the production region, the restored database in the recovery region can be deleted. The database in the production region then relies on geo-restore for DR protection again. 

In step 5, resources in the recovery region, including the recovery servers and pools, are deleted.      

## Run the repatriation script
Now let's assume the outage is resolved and run the repatriation script.  This script reverts tenants you didn't modify to their original databases.  It then copies the databases you updated earlier to the production region, replacing the corresponding databases there.    
  
1. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 2, Recover the SaaS app into a recovery region by restoring from geo-redundant backups**

1. Press **F5** to run the recovery script. The repatriation of the changed databases will take several minutes.
1. While the script is running, refresh the Events Hub page (http://events.wingtip-dpt.&lt;user&gt;.trafficmanager.net - substitute &lt;user&gt; with your deployment's user value)
	* Notice that all the tenants are online and accessible throughout this process.
1. Click on the Fabrikam Jazz Club to open it. If you did not modify this tenant, notice from the footer that the server is already reverted to the original production server.
1. Open or refresh the Contoso Concert Hall events page and notice from the footer that the database is still on the _-recovery_ server initially.  
1. Refresh the Contoso Concert Hall events page when the repatriation process completes and notice that the server is now the original server.

## Clean up recovery region resources after repatriation
Once repatriation completes, it's safe to delete the resources in the recovery region.  The restore process creates all the recovery resources in a recovery resource group.  Using a separate resource group allows them to be deleted together with a single action.
1. Open the [Azure portal](https://portal.azure.com) and delete the **ADD NAME OF RG HERE** resource group.
	* Deleting these resources promptly is recommended as it stops billing for them.

## Design the application to ensure app and database are colocated 
The sample app is designed so that the application always connects from aninstance in the same region as the tenant database. This design reduces latency between the application and the database.  This optimization assumes the app-to-database interaction is chattier than the user-to-app interaction.  

Tenant databases may be spread across recovery and original regions for some time during repatriation.  The app looks up the region hosting the tenant database server (by doing a DNS lookup on the server name). If the application instance isn't in the same region as the database, it redirects to the application instance in the same region as the database server.  

## Next steps

In this tutorial you learned how to:

* Sync tenant configuration data into the tenant catalog database
* Use tenant aliases to ensure no application changes are required during the recovery process 
* Restore Azure SQL servers, elastic pools, and Azure SQL databases into a recovery region
* Repatriate recovered databases that have been updated to the original production region

<!--Now, try the [Recover a multi-tenant SaaS application using geo-replication]() to learn how to geo-replication can dramatically reduce the time needed to recover a large-scale multi-tenant application.
-->
## Additional resources

* [Additional tutorials that build upon the Wingtip SaaS application](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-wtp-overview#sql-database-wingtip-saas-tutorials)
