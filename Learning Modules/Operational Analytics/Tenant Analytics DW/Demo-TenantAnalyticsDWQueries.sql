-- *******************************************************
-- SAMPLE QUERY
-- *******************************************************

-- Get a summary of all ticket sales from all tenants
SELECT  VenueName, 
		CONVERT(VARCHAR(30), SUM(PurchaseTotal), 1) AS TotalSales
FROM    dbo.AllTicketsPurchasesfromAllTenants 
GROUP   BY VenueName  
ORDER   BY SUM(PurchaseTotal) DESC;  
GO
