## WingtipSaaS
Wingtip Tickets Platform sample SaaS application and management scripts.

This project provides a sample SaaS application that embodies many common SaaS patterns that can be used with Azure SQL Database.  The sample is based on an event-management and ticket-selling scenario for small venues.  Each venue is a 'tenant' of the SaaS application.  The sample uses a database-per-tenant model, with a database created for each venue.  These databases are hosted in elastic database pools to provide easy performance management, and to cost-effectively accommodate the unpredictable usage patterns of these small venues and their customers.  An additional catalog database holds the mapping between tenants and their databases.  This mapping is managed using the Shard Map Management features of the Elastic Scale Client Library.  

The basic application, which includes three pre-defined databases for three venues, can be installed in your Azure subscription under a single ARM resource group.  To uninstall the application, delete the resource group from the Azure Portal. 

NOTE: if you install the application you will be charged for the Azure resources created.  Actual costs incurred are based on your subscription offer type but are nominal if the application is not scaled up unreasonably and is deleted promptly after you have finished exploring the tutorials.

More information about the sample app and the associated tutorials are here: [https://aka.ms/sqldbsaastutorial](https://aka.ms/sqldbsaastutorial)

To deploy the app to Azure, click the link below.  Deploy the app in a new resource group, and provide a short *user* value that will be appended to several resource names to make them globally unique.  Your initials and a number is a good pattern to use.


<a href="http://aka.ms/deploywtpapp" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>


After deployment completes, launch the app by browsing to ```http://events.wtp.USER.trafficmanager.net```, substituting *USER* with the value you set during deployment. 

**IMPORTANT:** If you download and extract the repo or [Learning Modules](https://github.com/Microsoft/WingtipSaaS/tree/master/Learning%20Modules) from a zip file, make sure you unblock the .zip file before extracting. Executable contents (scripts, dlls) may be blocked by Windows when zip files are downloaded from an external source and extracted.

To avoid scripts from being blocked by Windows:

1. Right click the zip file and select **Properties**.
1. On the **General** tab, select **Unblock** and select **OK**.


## License
Microsoft Wingtip SaaS sample application and tutorials are licensed under the MIT license. See the [LICENSE](https://github.com/Microsoft/WingtipSaaS/blob/master/license) file for more details.

# Contributing

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
