# Recover a multi-tenant SaaS application using geo-restore from database backups

In this tutorial, you learn how to recover a multi-tenant SaaS database-per-tenant application after an outage. You use _geo-restore_ to recover the catalog and tenant databases from automatically maintained geo-redundant backups into a different 'recovery' region. While geo-restore is the lowest-cost disaster recovery mechanism, restoring large numbers of databases can take a long time. The process must be carefully orchestrated so that recovery is as fast as possible.

You'll learn how to:

* Sync database and elastic pool configuration info into the tenant catalog
* Recover servers, elastic pools, and databases into a different region using the most recent configuration info
* Use tenant database aliases so that changes to connection strings are not required when recovering databases 
 

To complete this tutorial, make sure the following prerequisites are completed:
* The Wingtip Tickets SaaS database per tenant app is deployed. To deploy in less than five minutes, see [Deploy and explore the Wingtip Tickets SaaS database per tenant application](saas-dbpertenant-get-started-deploy.md)
* Azure PowerShell is installed. For details, see [Getting started with Azure PowerShell](https://docs.microsoft.com/powershell/azure/get-started-azureps)



## Introduction to the SaaS application geo-restore recovery pattern

![Recovery Architecture](TutorialMedia/recoveryarchitecture.png)

Disaster recovery is an important consideration for many applications, whether for compliance reasons or business continuity.  DR addresses the possibility of a natural disaster or a prolonged outage of a service. In a DR scenario, the goal is to recover your application and data and continue processing with the least possible interruption. In this tutorial, you explore recovering a SaaS application and its databases into a recovery region.  And later you repatriate the application to its original region without interruption.     

Recovering a SaaS app can be challenging, particularly if the app is operating at scale. You need to: 
* Quickly provision servers and pools in the recovery region to reserve capacity for all existing tenants and to allow new tenants to be provisioned  
* Deploy the app in the recovery region and enable it to start provisioning new tenants as soon as possible
* Restore tenant databases in parallel across all pools to ensure maximum restore throughput
* Submit restore requests in batches to avoid service throttling limits
* Restore tenants in priority order to minimize impact on key customers 
* Enable the app to connect to recovered databases without changing connection strings
* Allow the restore process to be canceled in mid-flight.  Canceling requires you revert all databases not yet recovered, or recovered but not yet updated, to the copy in the original region.  Reverting to the original database prevents data loss and reduces the number of databases that need repatriation
* Repatriate recovered databases that have been modified to the original production region.  Repatriation should have no impact on tenants. 
* Ensure the app instance used to connect to a tenant database is colocated in the same region to minimize latency 

In this tutorial, these challenges are addressed using features of Azure SQL Database and the Azure platform:

* Resource Management templates are used to create a mirror image of the production servers and elastic pools in the recovery region, and to create a separate server and pool for provisioning new tenants 
* [Geo-restore ](https://docs.microsoft.com/azure/sql-database/sql-database-disaster-recovery) is used to recover the catalog and tenant databases from automatically maintained geo-redundant backups. 
* DNS aliases are used for each database to allow connections to be routed to recovered or repatriated databases without changing or reconfiguring the app.  Switching the active database requires only changing the alias    
* Restore requests are submitted asynchronously (without waiting for requests to be processed). SQL database queues the requests for each pool and processes them in order in batches to prevent overloading pool resources.
* _Geo-replication_ is used to repatriate databases to the original region after the outage. Using geo-replication ensures there is no data loss and minimal impact on the tenant.   

## Get the disaster recovery management scripts 

The recovery scripts used in this tutorial are available in the [Wingtip Tickets SaaS database per tenant GitHub repository](https://github.com/Microsoft/WingtipTicketsSaaS-DbPerTenant/tree/feature-DR-georestore). Check out the [general guidance](saas-tenancy-wingtip-app-guidance-tips.md) for steps to download and unblock the Wingtip Tickets management scripts.

## Sync tenant configuration

In this first step, you sync the configuration of your production servers, elastic pools, and databases into the tenant catalog.  This information is used later to configure a mirror image environment in the recovery region.

Note: the sync process is implemented here as local Powershell job. In a real-world scenario, this process should be implemented as a reliable service of some kind.

1. In the _PowerShell ISE_, open the ...\Learning Modules\UserConfig.psm1 file. Replace `<resourcegroup>` and `<user>` on lines 10 and 11.  Use the resource group and user value entered when you deployed the Wingtip Tickets app.

2. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 1, Start a background job that syncs tenant server, and pool configuration info into the catalog**

3. Press **F5** to run the sync script. A new PowerShell session is opened to sync the configuration of tenant resources.
![Sync process](TutorialMedia/syncprocess.png)

Leave the PowerShell window running in the background and continue with the rest of the tutorial. 

## Restore tenant resources into the recovery region

The recovery process ensures that required resources are reserved, tenant resources are recovered as fast as possible, and normal business operations resume with the least interruption. The process comprises the following steps:

1. Disable the Traffic Manager endpoint for the web app in the original production region. Disabling the endpoint prevents users from connecting to the app in an invalid state should the region come online during recovery.

1. Provision the recovery catalog server in the recovery region and then geo-restore the catalog database on the server using a Resource Manager template. Update the catalog alias to point to the recovery catalog database once it has been restored.

1. Mark all existing tenants in the recovery catalog as offline to prevent access to the tenant databases before they are restored.

1. Provision an instance of the app in the recovery region plus a server and elastic pool to be used for provisioning new tenants.
		
1. Provision the recovery server and pool resources required for restoring the existing tenant databases using an Azure Resource Manager template. Provisioning pools first reserves the capacity that will be needed for database recovery. 

1. Enable the Traffic Manager endpoint for the web app in the recovery region.  At this stage the application is able to support provisioning new tenants.   

1. Once all elastic pools are provisioned, submit batches of requests to restore databases across all pools in priority order. Batches are organized so that database restores run in parallel across all pools.  Asynchronous restore requests are used to allow them to be submitted quickly and queued for execution without waiting for completion.

1. Poll the database service to determine when databases have been restored.  Once a tenant database is restored, update the tenant alias to point to the recovered database instance and mark the tenant as online in the catalog.  Tenant databases can be accessed by the application as soon as they're marked online in the catalog.

Now run the recovery script:

1. In the *PowerShell ISE*, open the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\Demo-RestoreFromBackup.ps1 script and set the following values:
	* **$DemoScenario = 2, Recover the SaaS app into a recovery region by restoring from geo-redundant backups**

2. Press **F5** to run the recovery script that automates the entire recovery process.  The script provisions new servers and pools, and restores the catalog and tenant databases into the recovery region. The recovery region is the paired region associated with the region in which you deployed the application. For more information, see [Azure paired regions](https://docs.microsoft.com/en-us/azure/best-practices-availability-paired-regions). 

	You can monitor the status of the recovery process by watching the console section of the PowerShell window.
	[insert screenshot of powershell window with code running]

	Explore the code behind the recovery jobs that are running by exploring the PowerShell scripts in the ...\Learning Modules\Business Continuity and Disaster Recovery\DR-RestoreFromBackup\RecoveryJobs folder.

When the recovery process completes, the application is fully functional in the recovery region. Open the Wingtip Tickets Events Hub in your web browser (http://events.wingtip-dpt.<USER\>.trafficmanager.net - substitute <USER> with your deployment's user value).  Notice the value reported for the catalog server in the footer is the catalog recovery server in the recovery region.

![Recovered tenants list](TutorialMedia/recoveredcatalogserver.png)

Click on Contoso Concert Hall and open its event browse page. Notice the tenants server is the tenants recovery server in the recovery region.


 [open the Azure portal](https://portal.azure.com) and inspect the recovered tenant resources in the recovery region resource group. Additionally,  


## Repatriate application to the original production region

As a final step in the recovery process, the application and databases are repatriated from the recovery region into its original production region.   

## Next steps

In this tutorial you learned how to:

* Sync tenant configuration data into the tenant catalog database
* Use tenant aliases to ensure no code changes are required during the recovery process 
* Restore Azure SQL servers, Elastic pools, and Azure SQL databases into a recovery region 

Now, try the [Recover a multi-tenant SaaS application using geo-replication]() to learn how to geo-replication can dramatically reduce the time needed to recover a large-scale multi-tenant application.

## Additional resources

* [Additional tutorials that build upon the Wingtip SaaS application](https://docs.microsoft.com/en-us/azure/sql-database/sql-database-wtp-overview#sql-database-wingtip-saas-tutorials)
