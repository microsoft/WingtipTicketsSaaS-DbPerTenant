<#
.Synopsis
	Simulates customer ticket purchases for events in WTP tenant databases 
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
Import-Module "$PSScriptRoot\..\WtpConfig" -Force

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

        [ValidateRange(1,60)]
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
    [decimal] $variance = (-15, -10, -8, -5, -4, 0, 5, 10) | Get-Random 
    $curvePercent = $curvePercent + ($curvePercent * $variance/100)

    if ($curvePercent -lt 0) {$curvePercent = 0}
    elseif ($curvePercent -gt 100) {$curvePercent = 100}
    
    [decimal]$sales = ($curvePercent * $Seats / 100)

    [int]$roundedSales = [math]::Ceiling($sales)

    return $roundedSales 
}

## MAIN SCRIPT ## ----------------------------------------------------------------------------

# Ensure logged in to Azure
Initialize-Subscription

$startTime = Get-Date

$AdminUserName = $config.TenantAdminUsername
$AdminPassword = $config.TenantAdminPassword

$ServerName = $config.TenantServerNameStem + $WtpUser.ToLower()
  
<# uncomment to generate tickets for the golden databases   
$WtpResourceGroupName = "wingtip-gold"
$ServerName = "wingtip-customers-gold"
#>

$FullyQualifiedServerName = $ServerName + ".database.windows.net" 

# load fictitious customer names, postal codes, 
$fictitiousNames = Import-Csv -Path ("$PSScriptRoot\FictitiousNames.csv") -Header ("Id","FirstName","LastName","Language","Gender")
$fictitiousNames = {$fictitiousNames}.Invoke()
$customerCount = $fictitiousNames.Count
$postalCodes = Import-Csv -Path ("$PSScriptRoot\SeattleZonedPostalCodes.csv") -Header ("Zone","PostalCode")

# load the full set of event sales curves
$importCurves = Import-Csv -Path ("$PSScriptRoot\WtpSalesCurves1.csv") -Header ("Curve","1", "5","10","15","20","25","30","35","40","45","50","55","60")
$curves = @{}
foreach ($importCurve in $importCurves) 
{
    $curves += @{$importCurve.Curve = $importCurve}
}

# create different sets of curves that reflect different venue/event popularities 
$popularCurves = $curves.MadRush,$curves.Rush,$curves.SShapedHigh,$curves.FastBurn, $curves.StraightLine, $curves.LastMinuteRush
$moderateCurves = $Curves.Rush,$Curves.SShapedMedium, $Curves.MediumBurn, $Curves.LastMinute
$unpopularCurves = $curves.SShapedLow, $curves.QuickFizzle, $curves.SlowBurn,$curves.LastGasp, $curves.Disappointing

# initialize SQL script for creating fictious customer, same customers are used for all venues, names will be picked at random for events
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

    # shorten to ensure fits in limited length column
    if($alias.Length -gt 38) { $alias = $alias.Substring(0,38) }

    # oh look, they all use outlook as their email provider...
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
    $venueTickets = 0
     
    $venueDatabaseName = $venue.Location.Database
     
    # set the venue popularity, which determines the sales curves used: 1=popular, 2=moderate, 3=unpopular

    # pre-defined venues use same popularity every time 
    if     ($venueDatabaseName -eq 'contosoconcerthall') { $popularity = "popular"}
    elseif ($venueDatabaseName -eq 'fabrikamjazzclub')   { $popularity = "moderate"}
    elseif ($venueDatabaseName -eq 'dogwooddojo')        { $popularity = "unpopular"}
    else
    {
        # set random popularity for all other venues   
        $popularity = ('popular','moderate','unpopular') | Get-Random 
    }

    # assign the venue curves based on popularity 
    switch ($popularity) 
    {
        "popular" {$venueCurves = $popularCurves}
        "moderate" {$venueCurves = $moderateCurves}
        "unpopular" {$venueCurves = $unpopularCurves}
    }

    Write-Output "Purchasing tickets for $venueDatabaseName ($popularity)"

    # add customers to the venue
    $results = Invoke-SqlAzureWithRetry `
                -Username "$AdminUserName" -Password "$AdminPassword" `
                -ServerInstance $venue.Location.Server `
                -Database $venueDatabaseName `
                -Query $customersSql 

    # initialize ticket purchase identity for this venue
    $ticketPurchaseId = 1

    # initialize SQL insert batch counters for tickets and ticket purchases
    $tBatch = 1
    $tpBatch = 1
    
    # initialize SQL batches for tickets and ticket purchases
    $ticketSql = "
        INSERT INTO [dbo].[Tickets] ([RowNumber],[SeatNumber],[EventId],[SectionId],[TicketPurchaseId]) VALUES `n"
    
    $ticketPurchaseSql = `
       "SET IDENTITY_INSERT [dbo].[TicketPurchases] ON
        INSERT INTO [dbo].[TicketPurchases] ([TicketPurchaseId],[CustomerId],[PurchaseDate],[PurchaseTotal]) VALUES`n" 

    # get total number of seats in venue
    $command = "SELECT SUM(SeatRows * SeatsPerRow) AS Capacity FROM Sections"        
    $capacity = Invoke-SqlAzureWithRetry `
                -Username "$AdminUserName" -Password "$AdminPassword" `
                -ServerInstance $venue.Location.Server `
                -Database $venue.Location.Database `
                -Query $command

    # get events for this venue
    $command = "
    SELECT EventId, EventName, Date FROM [dbo].[Events]
    ORDER BY Date ASC"
       
    $events = Invoke-SqlAzureWithRetry `
                -Username "$AdminUserName" -Password "$AdminPassword" `
                -ServerInstance $venue.Location.Server `
                -Database $venue.Location.Database `
                -Query $command 

    $eventCount = 1
    foreach ($event in $events) 
    {
        if 
        (
            $eventCount -eq $events.Count -and 
            (
                $venueDatabaseName -eq 'contosoconcerthall' -or 
                $venueDatabaseName -eq 'fabrikamjazzclub' -or 
                $venueDatabaseName -eq 'dogwooddojo'
            )
        )
        {
            # don't generate tickets for the last event for the pre-defined venues so they can be deleted    
            break
        }

        # assign a sales curve for this event from the set assigned to this venue
        $eventCurve = $venueCurves | Get-Random

        Write-Host -NoNewline "  Processing event '$($event.EventName)'..."

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

        # ticket sales start date as (event date - 60)
        $ticketStart = $event.Date.AddDays(-60)

        $today = Get-Date

        # loop over 60 day sales period          
        for($day = 1; $day -le 60 ; $day++)  
        {
            # stop selling tickets when all sold 
            if ($eventTickets -ge $capacity.Capacity) 
            {
                break
            }
 
            $purchaseDate = $ticketStart.AddDays($day)

            # stop selling tickets after today
            if ($purchaseDate -gt $today)
            {
                break
            }

            # find the number of tickets to purchase this day based on this event's curve
            [int]$ticketsToPurchase = Get-CurvedSalesForDay -Curve $eventCurve -Day $day -Seats $capacity.Capacity
            
            # if no tickets to sell this day, skip this day
            if ($ticketsToPurchase -eq 0) 
            {
                continue
            }

            $ticketsPurchased = 0            
            while ($ticketsPurchased -lt $ticketsToPurchase -and $seating.Count -gt 0 )
            {
                ## buy tickets on a customer-by-customer basis

                # pick a random customer Id
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
                
                # modify customer order if insufficient seats available in the chosen section (not so realistic but ensures all seats sell quickly)
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

        Write-Output " $eventTickets tickets purchased"
        
        $eventCount ++
    
    # per event purchases
    }

    Write-Output "  $venueTickets tickets purchased for $($venue.Location.Database)"

    # Finalize batched SQL commands for this venue and execute

    Write-Output "    Inserting TicketPurchases" 
        
    $ticketPurchaseSql = $ticketPurchaseSql.TrimEnd((" ",",","`n")) + ";"
    $ticketPurchaseSql += "`nSET IDENTITY_INSERT [dbo].[TicketPurchases] OFF"

    $ticketPurchasesExec = Invoke-SqlAzureWithRetry `
        -Username "$AdminUserName" `
        -Password "$AdminPassword" `
        -ServerInstance $venue.Location.Server `
        -Database $venue.Location.Database `
        -Query $ticketPurchaseSql `
        -QueryTimeout 120 

    Write-Output "    Inserting Tickets " 
               
    $ticketSql = $ticketSql.TrimEnd((" ",",","`n")) + ";"

    $ticketsExec = Invoke-SqlAzureWithRetry `
        -Username "$AdminUserName" `
        -Password "$AdminPassword" `
        -ServerInstance $venue.Location.Server `
        -Database $venue.Location.Database `
        -Query $ticketSql `
        -QueryTimeout 120 
    
# per venue purchases

}

Write-Output "$totalTicketPurchases TicketPurchases total"
Write-Output "$totalTickets Tickets total"

$duration =  [math]::Round(((Get-Date) - $startTime).Minutes)

Write-Output "Duration $duration minutes"