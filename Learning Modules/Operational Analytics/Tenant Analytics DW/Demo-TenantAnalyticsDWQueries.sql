-- *******************************************************
-- SIMPLE ADHOC QUERY. Any others you would like to try?
-- *******************************************************

-- Get a summary of all ticket sales from all tenants
SELECT  VenueName, SUM(PurchaseTotal) as TotalSales
FROM    dbo.AllTicketsPurchasesfromAllTenants 
GROUP   BY VenueName  
ORDER   BY TotalSales DESC;  
GO