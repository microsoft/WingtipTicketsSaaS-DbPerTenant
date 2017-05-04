# Helper script for invoking Apply-SQLCommandToTenantDatabases.
# Crude way to apply a one-time script against tenant dbs in catalog.  Use Elastic Jobs for any serious work...! 

# SQL command to be applied.  Script should be idempotent as will retry on error. No results are returned, check dbs for success.  
$commandText = "
    DROP VIEW IF EXISTS VenueEvents
    GO
    CREATE VIEW VenueEvents AS
    SELECT (SELECT TOP 1 VenueName FROM Venue) AS VenueName, EventId, EventName, Date FROM [events]
    GO

    DROP VIEW IF EXISTS VenueTicketPurchases
    GO
    CREATE VIEW VenueTicketPurchases AS
    SELECT (SELECT TOP 1 VenueName FROM Venue) AS VenueName, TicketPurchaseId, PurchaseDate, PurchaseTotal, CustomerId FROM [TicketPurchases]
    GO

    DROP VIEW IF EXISTS VenueTickets 
    GO   
    CREATE VIEW VenueTickets AS 
    SELECT (SELECT TOP 1 VenueName FROM Venue) AS VenueName, TicketId, RowNumber, SeatNumber, EventId, SectionId, TicketPurchaseId FROM [Tickets]
    GO
    "

# query timeout in seconds
$queryTimeout = 60

## ------------------------------------------------------------------------------------------------ 

Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement" -Force
Import-Module "$PSScriptRoot\..\UserConfig" -Force

# Get Azure credentials if not already logged on,  Use -Force to select a different subscription 
Initialize-Subscription -NoEcho

# Get the resource group and user names used when the WTP application was deployed from UserConfig.psm1.  
$wtpUser = Get-UserConfig
 
& $PSScriptRoot\Invoke-SqlCmdOnTenantDatabases `
    -WtpResourceGroupName $wtpUser.ResourceGroupName `
    -WtpUser $wtpUser.Name `
    -CommandText $commandText `
    -QueryTimeout $queryTimeout
