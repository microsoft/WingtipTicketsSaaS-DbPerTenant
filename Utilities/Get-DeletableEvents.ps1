Get-DeletableEvent

<#

select * from EventsWithNoTickets

DELETE FROM TicketPurchases 
FROM TicketPurchases AS tp
INNER JOIN Tickets AS t ON t.TicketPurchaseId = tp.TicketPurchaseId
WHERE t.EventId = 1

select * from EventsWithNoTickets

DELETE FROM Events WHERE EventId = 1


#>