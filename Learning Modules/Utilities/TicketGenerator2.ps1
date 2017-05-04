<#
.Synopsis
	Simulates customer ticket purchases for events in Wingtip SaaS tenant databases 
.DESCRIPTION
	Adds customers and creates tickets for events in tenant (venue) databases. Does not 
    create tickets for the last event in each database to allow this to be deleted to 
    demonstrate point-in-time restore.
#>

[CmdletBinding()]
Param
(
	# Resource Group Name entered during deployment 
	[Parameter(Mandatory=$true)]
	[String]
	$WtpResourceGroupName,

	# The user name used entered during deployment
	[Parameter(Mandatory=$true)]
	[String]
	$WtpUser
)
Import-Module "$PSScriptRoot\..\Common\SubscriptionManagement"
Import-Module "$PSScriptRoot\..\Common\CatalogAndDatabaseManagement" -Force
Import-Module "$PSScriptRoot\..\WtpConfig" -Force -Verbose

$ErrorActionPreference = "Stop"

$config = Get-Configuration

$catalog = Get-Catalog -ResourceGroupName $WtpResourceGroupName -WtpUser $WtpUser

## Functions

function Get-PaddedNumber
{
    param ([int] $Number)

    if ($Number -lt 10) {return "000$Number"}
    if ($number -lt 100) {return "00$Number"}
    if ($Number -lt 1000) {return "0$Number"}
    return $Number.ToString()        
}

function Get-CurvedSalesForDay 
{
    param 
    (
    [object] $Curve,

    [validaterange(1,60)]
    [int] $Day,

    [int] $Seats

    )
    
    [decimal] $curvePercent = 0   
    
    if ($Day -eq 1) { $curvePercent = $Curve.1 } 
    elseif ($Day -le 5) { $curvePercent = ($Curve.5 / 4) }   
    elseif ($Day -le 10) { $curvePercent = ($Curve.10 / 5) }     
    elseif ($Day -le 15) { $curvePercent = ($Curve.15 / 5) }
    elseif ($Day -le 20) { $curvePercent = ($Curve.20 / 5) }
    elseif ($Day -le 25) { $curvePercent = ($Curve.25 / 5) }
    elseif ($Day -le 30) { $curvePercent = ($Curve.30 / 5) }
    elseif ($Day -le 35) { $curvePercent = ($Curve.35 / 5) }    
    elseif ($Day -le 40) { $curvePercent = ($Curve.40 / 5) }
    elseif ($Day -le 45) { $curvePercent = ($Curve.45 / 5) }
    elseif ($Day -le 50) { $curvePercent = ($Curve.50 / 5) }
    elseif ($Day -le 55) { $curvePercent = ($Curve.55 / 5) }
    else { $curvePercent = ($Curve.60 / 5) }

    # add some random variation
    [decimal] $variance = (-10, -8, -5, -4, -2, 0, 2, 4, 5, 8, 10) | Get-Random 
    $curvePercent = $curvePercent + ($curvePercent * $variance/100)
    
    [decimal]$sales = ($curvePercent * $Seats / 100)

    [int]$roundedSales = [math]::Ceiling($sales)

    return $roundedSales 
}

function Get-VenueCurves
{
    param(
        [string] $Venue,

        [object] $Curves
    )
       

    if ($Venue -eq 'contosoconcerthall')
    {
        # popular
        $VenueCurves = $Curves.MadRush,$Curves.Rush,$Curves.SShaped,$Curves.FastBurn, $Curves.StraightLine
    }
    elseif ($Venue -eq 'fabrikamjazzclub')
    {
        # moderate
        $VenueCurves = $Curves.Rush,$Curves.SShaped,$Curves.StraightLine, $Curves.LastMinute
    }
    elseif ($Venue -eq 'dogwooddojo')
    {
        # less popular
        $VenueCurves = $Curves.QuickFizzle,$Curves.SShaped,$Curves.StraightLine, $Curves.SlowBurn,$Curves.LastMinute
    }
    else
    {
        $VenueCurves = $Curves
    }

    return $VenueCurves
}

## MAIN SCRIPT ## ----------------------------------------------------------------------------

# Ensure logged in to Azure
Initialize-Subscription

$AdminUserName = $config.TenantAdminUsername
$AdminPassword = $config.TenantAdminPassword

$ServerName = $config.TenantServerNameStem + $WtpUser.ToLower()
  
<# uncomment to generate tickets for the golden databases   
$WtpResourceGroupName = "wingtip-gold"
$ServerName = "wingtip-customers-gold"
#>

$FullyQualifiedServerName = $ServerName + ".database.windows.net" 

# load fictitious customer names, postal codes, event sales curves
$fictitiousNames = Import-Csv -Path ("$PSScriptRoot\FictitiousNames.csv") -Header ("Id","FirstName","LastName","Language","Gender")
$fictitiousNames = {$fictitiousNames}.Invoke()
$customerCount = $fictitiousNames.Count
$postalCodes = Import-Csv -Path ("$PSScriptRoot\SeattleZonedPostalCodes.csv") -Header ("Zone","PostalCode")
$importCurves = Import-Csv -Path ("$PSScriptRoot\WtpSalesCurves1.csv") -Header ("Curve","1", "5","10","15","20","25","30","35","40","45","50","55","60")
$curves = @{}
foreach ($importCurve in $importCurves) 
{
    $curves += @{$importCurve.Curve = $importCurve}
}

# set up SQl script for creating fictious customers, same people will be used for all venues and events
$customersSql  = "
    DELETE FROM [dbo].[Tickets]
    DELETE FROM [dbo].[TicketPurchases]
    DELETE FROM [dbo].[Customers]
    SET IDENTITY_INSERT [dbo].[Customers] ON 
    INSERT INTO [dbo].[Customers] 
    ([CustomerId],[FirstName],[LastName],[Email],[PostalCode],[CountryCode]) 
    VALUES `n"

# all customers are located in the US
$CountryCode = 'USA'
$CustomerId = 0
while ($fictitiousNames.Count -gt 0) 
{
    # get a name at random then remove from the list
    $name = $fictitiousNames | Get-Random
    $fictitiousNames.Remove($name) > $null

    $firstName = $name.FirstName.Replace("'","").Trim()
    $lastName = $name.LastName.Replace("'","").Trim()
    
    # form the customers email address
    $alias = ($firstName + "." + $lastName).ToLower()

    if($alias.Length -gt 38) { $alias = $alias.Substring(0,38) }

    # oh, look, they all use outlook as their email provider...
    $email = $alias + "@outlook.com"

    # randomly assign a postal code
    $postalCode = ($postalCodes | Get-Random).PostalCode

    $customerId ++

    $customersSql += "      ($customerId,'$firstName','$lastName','$email','$postalCode','$CountryCode'),`n"

}

$customersSql = $customersSql.TrimEnd(("`n",","," ")) + ";`nSET IDENTITY_INSERT [dbo].[Customers] OFF"

# Get all the venue databases in the catalog
$venues = Get-Shards -ShardMap $catalog.ShardMap

$totalTicketPurchases = 0
$totalTickets = 0

# load characteristics of known venues from config

foreach ($venue in $venues)
{
    Write-Output "Purchasing tickets for $($venue.Location.Database)"
    $venueTickets = 0

    # add customers to the venue
    $results = Invoke-SqlAzureWithRetry `
                -Username "$AdminUserName" -Password "$AdminPassword" `
                -ServerInstance $venue.Location.Server `
                -Database $venue.Location.Database `
                -Query $customersSql 

    # reset ticket purchase identity
    $ticketPurchaseId = 1

    # reset SQL insert batch counters for tickets and ticket purchases
    $tBatch = 1
    $tpBatch = 1
    
    # initialize SQL batches for tickets and ticket purchases
    $ticketSql = "
        INSERT INTO [dbo].[Tickets] ([RowNumber],[SeatNumber],[EventId],[SectionId],[TicketPurchaseId]) VALUES `n"
    $ticketPurchaseSql = `
       "SET IDENTITY_INSERT [dbo].[TicketPurchases] ON
        INSERT INTO [dbo].[TicketPurchases] ([TicketPurchaseId],[CustomerId],[PurchaseDate],[PurchaseTotal]) VALUES`n" 

    # get venue characteristics (popularity) or assign

    # set probability for sales curves for this venue

    # set relative popularity of sections from config or assign  

    # get total number of seats in venue
    $command = "SELECT SUM(SeatRows * SeatsPerRow) AS TotalSeats FROM Sections"        
    $totalSeats = Invoke-SqlAzureWithRetry `
                -Username "$AdminUserName" -Password "$AdminPassword" `
                -ServerInstance $venue.Location.Server `
                -Database $venue.Location.Database `
                -Query $command

    # get events for this venue
    $command = "SELECT EventId, EventName, Date FROM [dbo].[Events]"        
    $events = Invoke-SqlAzureWithRetry `
                -Username "$AdminUserName" -Password "$AdminPassword" `
                -ServerInstance $venue.Location.Server `
                -Database $venue.Location.Database `
                -Query $command 

    foreach ($event in $events) 
    {
        $eventTickets = 0

        # get seating sections and prices for this event
        $command = "
            SELECT s.SectionId, s.SectionName, SeatRows, SeatsPerRow, es.Price
            FROM [dbo].[EventSections] AS es
            INNER JOIN [dbo].[Sections] AS s ON s.SectionId = es.SectionId
            WHERE es.EventId = $($event.EventId)"
        $sections = @()
        $sections += Invoke-SqlAzureWithRetry `
                    -Username "$AdminUserName" -Password "$AdminPassword" `
                    -ServerInstance $venue.Location.Server `
                    -Database $venue.Location.Database `
                    -Query $command

        # process sections to create collections of seats from which purchased tickets will be drawn
        $seating = @{}
        $sectionNumber = 1
        foreach ($section in $sections)
        {
            $sectionSeating = @{}

            for ($row = 1;$row -le $section.SeatRows;$row++)
            {
                for ($seatNumber = 1;$seatNumber -le $section.SeatsPerRow;$seatNumber++)
                {
                    # create the seat and assign its price
                    $seat = New-Object psobject -Property @{
                                SectionId = $section.SectionId
                                Row = $row
                                SeatNumber = $seatNumber
                                Price = $section.Price
                                }
                    
                    $index = "$(Get-PaddedNumber $row)/$(Get-PaddedNumber $seatNumber)" 
                    $sectionSeating += @{$index = $seat}                    
                }
            }           

            $seating += @{$sectionNumber = $sectionSeating} 
            $sectionNumber ++
        }            

        ## set event characteristics

        # set event popularity (likelihood of sellout) 

        # assign a sales curve for this event from the set associated with this venue
        $venueCurves = Get-VenueCurves -Venue $venue.Location.Database -Curves $curves
        $curve = $venueCurves | Get-Random

        # set the tickets to be sold based on event popularity and relative popularity of sections

        # ticket sales start date as (event date - 60)
        $ticketStart = $event.Date.AddDays(-60)

        $today = Get-Date

        # loop over 60 day sales period          
        for($day = 1; $day -le 60 ; $day++)  
        {
            # stop selling tickets when all sold 
            if ($eventTickets -ge $totalSeats.TotalSeats) 
            {
                break
            }
 
            $purchaseDate = $ticketStart.AddDays($day)

            # stop selling tickets after today
            if ($purchaseDate -gt $today)
            {
                break
            }

            # use the curve to find the number of tickets to purchase for this day
            [int]$ticketsToPurchase = Get-CurvedSalesForDay -Curve $curve -Day $day -Seats $totalSeats.TotalSeats
            
            # if no tickets to sell this day, skip this day
            if ($ticketsToPurchase -eq 0) 
            {
                continue
            } 

            $ticketsPurchased = 0            
            while ($ticketsPurchased -lt $ticketsToPurchase -and $seating.Count -gt 0 )
            {
                # buy tickets on a customer-by-customer basis

                # pick random customer Id
                $customerId = Get-Random -Minimum 1 -Maximum $customerCount  
                
                # pick number of tickets to purchase (2-10 per person)
                $ticketOrder = Get-Random -Minimum 2 -Maximum 10
                
                # ensure ticket order does not cause purchases to exceed tickets to buy for this day
                $remainingTicketsToBuyThisDay = $ticketsToPurchase - $ticketsPurchased
                if ($Ticketorder -gt $remainingTicketsToBuyThisDay)
                {
                    $ticketOrder = $remainingTicketsToBuyThisDay
                }

                # select seating section (could extend here to bias by section popularity)
                $preferredSectionSeatingKey = $seating.Keys | Get-Random 
                $preferredSectionSeating = $seating.$preferredSectionSeatingKey
                
                # modify customer order if insufficient seats available in the chosen section (not so realistic but ensures all seats sold quickly)
                if ($ticketOrder -gt $preferredSectionSeating.Count)
                {
                    $ticketOrder = $preferredSectionSeating.Count
                }

                $PurchaseTotal = 0                                  

                # assign seats from the chosen section
                $seatingAssigned = $false                
                while ($seatingAssigned -eq $false)
                {
                    # assign seats to this order
                    for ($s = 1;$s -le $ticketOrder; $s++)
                    {
                        $purchasedSeatKey = $preferredSectionSeating.Keys| Sort | Select-Object -First 1 
                        $purchasedSeat = $preferredSectionSeating.$purchasedSeatKey

                        # set time of day of purchase - distributed randomly over prior 24 hours
                        $mins = Get-Random -Maximum 1440 -Minimum 0
                        $purchaseDate = $purchaseDate.AddMinutes(-$mins)

                        $PurchaseTotal += $purchasedSeat.Price
                        $ticketsPurchased ++
                        
                        # add ticket to tickets batch

                        # max of 1000 inserts per batch
                        if($tBatch -ge 1000)
                        {
                            # finalize current INSERT and start new INSERT statements and reset batch counter                                                                
                            $ticketSql = $ticketSql.TrimEnd((" ",",","`n")) + ";`n`n"                     
                            $ticketSql += "INSERT INTO [dbo].[Tickets] ([RowNumber],[SeatNumber],[EventId],[SectionId],[TicketPurchaseId]) VALUES `n"                            
                            $tBatch = 0
                        }

                        $ticketSql += "($($purchasedSeat.Row),$($purchasedSeat.SeatNumber),$($event.EventId),$($purchasedSeat.SectionId),$ticketPurchaseId),`n"
                        $tBatch ++

                        # remove seat from available seats when sold
                        $preferredSectionSeating.Remove($purchasedSeatKey)
                        
                        # remove section when sold out
                        if ($preferredSectionSeating.Count -eq 0)
                        {
                            $seating.Remove($preferredSectionSeatingKey)
                        }                       
                                                 
                    }
                    # add ticket purchase to batch
                    if($tpBatch -ge 1000)
                    {
                        # finalize current INSERT and start new INSERT statements and reset batch counter                                                                
                        $ticketPurchaseSql = $ticketPurchaseSql.TrimEnd((" ",",","`n")) + ";`n`n"                     
                        $ticketPurchaseSql += "INSERT INTO [dbo].[TicketPurchases] ([TicketPurchaseId],[CustomerId],[PurchaseDate],[PurchaseTotal]) VALUES`n"
                        $tpBatch = 0
                    }

                    $ticketPurchaseSql += "($ticketPurchaseId,$CustomerId,'$purchaseDate',$PurchaseTotal),`n"
                    $tpBatch ++
                    
                    $seatingAssigned = $true
                    $ticketPurchaseId ++                                        
                }

                $totalTicketPurchases ++
                $totalTickets += $ticketOrder
                $eventTickets += $ticketOrder
                $venueTickets += $ticketOrder

            # per customer purchases
            }
                                   
        # daily purchases
        }

        Write-Output "$eventTickets tickets purchased for event $($event.EventName)"

    # per event purchases
    }

    Write-Output "$venueTickets tickets purchased for venue $($venue.Location.Database)"

    # Finalize the batched SQL commands for this venue and execute

    Write-Output "Inserting TicketPurchases to $($venue.Location.Database)" 
        
    $ticketPurchaseSql = $ticketPurchaseSql.TrimEnd((" ",",","`n")) + ";"
    $ticketPurchaseSql += "`nSET IDENTITY_INSERT [dbo].[TicketPurchases] OFF"

    $ticketPurchasesExec = Invoke-Sqlcmd `
        -Username "$AdminUserName" `
        -Password "$AdminPassword" `
        -ServerInstance $venue.Location.Server `
        -Database $venue.Location.Database `
        -Query $ticketPurchaseSql `
        -ConnectionTimeout 30 `
        -QueryTimeout 120 `
        -EncryptConnection

    Write-Output "Inserting tickets for $($venue.Location.Database)" 
               
    $ticketSql = $ticketSql.TrimEnd((" ",",","`n")) + ";"

    $ticketsExec = Invoke-Sqlcmd `
        -Username "$AdminUserName" `
        -Password "$AdminPassword" `
        -ServerInstance $venue.Location.Server `
        -Database $venue.Location.Database `
        -Query $ticketSql `
        -ConnectionTimeout 30 `
        -QueryTimeout 120 `
        -EncryptConnection
    
# per venue purchases

}

Write-Output "$totalTicketPurchases TicketPurchases total"
Write-Output "$totalTickets Tickets total"
