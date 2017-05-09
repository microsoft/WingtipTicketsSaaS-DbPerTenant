## WingtipSaaS
Wingtip Tickets Platform sample SaaS application and management scripts.

This project provides a sample SaaS application that embodies many common SaaS patterns that can be used with Azure SQL Database.  The sample is based on an event-management and ticket-selling scenario for small venues.  Each venue is a 'tenant' of the SaaS application.  The sample uses a database-per-tenant model, with a database created for each venue.  These databases are hosted in elastic database pools to provide easy performance management, and to cost-effectively accommodate the unpredictable usage patterns of these small venues and their customers.  An additional catalog database holds the mapping between tenants and their databases.  This mapping is managed using the Shard Map Management features of the Elastic Scale Client Library.  

The basic application, which includes three pre-defined databases for three venues, can be installed in your Azure subscription under a single ARM resource group.  To uninstall the application, delete the resource group from the Azure Portal. 

NOTE: if you install the application you will be charged for the Azure resources created.  Actual costs incurred are based on your subscription offer type but are nominal if the application is not scaled up unreasonably and is deleted promptly after you have finished exploring the tutorials.

More information about the sample app and the associated tutorials can be found here: [https://aka.ms/sqldbsaastutorial](https://aka.ms/sqldbsaastutorial)

<a href="http://aka.ms/deploywtpapp" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
    

## License
Microsoft Wingtip SaaS sample application and tutorials are licensed under the MIT license. See the [LICENSE](https://github.com/Microsoft/WingtipSaaS/blob/master/license) file for more details.

# Contributing

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
