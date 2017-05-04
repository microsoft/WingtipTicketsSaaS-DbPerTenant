--Summary of all ticket sales from all tenants
SELECT VenueName, SUM(PurchaseTotal) as TotalSales
FROM dbo.AllTicketsPurchasesfromAllTenants 
GROUP BY VenueName  
ORDER BY TotalSales DESC;  
GO