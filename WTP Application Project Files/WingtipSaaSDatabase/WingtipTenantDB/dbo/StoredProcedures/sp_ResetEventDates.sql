CREATE PROCEDURE [dbo].[sp_ResetEventDates]
    @StartHour int = 19,
    @StartMinute int = 00
AS
    SET NOCOUNT ON

    DECLARE @EventId int
    DECLARE @Index int = 1
    DECLARE @Offset int = ROUND(((-3 - (-5) - 1) * RAND() + (-5)), 0)    -- offset of the first event in days from current date   
    DECLARE @Interval int = ROUND(((5 - 2 - 1) * RAND() + 2), 0)   -- interval between each event
    DECLARE @OldEventDate datetime
    DECLARE @NewEventDate datetime
    DECLARE @Diff int
    DECLARE @BaseDate datetime = DATETIMEFROMPARTS(YEAR(CURRENT_TIMESTAMP),MONTH(CURRENT_TIMESTAMP),DAY(CURRENT_TIMESTAMP),@StartHour,@StartMinute,00,000)
    DECLARE EventCursor CURSOR FOR SELECT EventId FROM [dbo].[Events] 
    
    OPEN EventCursor
    FETCH NEXT FROM EventCursor INTO @EventId
    --
    WHILE @@Fetch_Status = 0
    BEGIN
        SET @OldEventDate = (SELECT top 1 [Date] from [Events] WHERE EventId=@EventId)
        SET @NewEventDate = DATEADD(Day,@Offset,@BaseDate)
        
        UPDATE [Events] SET [Date] = @NewEventDate WHERE EventId=@EventId 
        
        UPDATE TicketPurchases SET PurchaseDate = DATEADD(day,Diff,@NewEventDate)
        FROM TicketPurchases AS tp
        INNER JOIN (SELECT tp2.TicketPurchaseId, DATEDIFF(day,@OldEventDate,tp2.PurchaseDate) AS Diff 
                        FROM TicketPurchases AS tp2
                        INNER JOIN [Tickets] AS t ON t.TicketPurchaseId = tp2.TicketPurchaseId
                        INNER JOIN [Events] AS e ON t.EventId = e.EventId
                    WHERE e.EventId = @EventId) AS etp ON etp.TicketPurchaseId = tp.TicketPurchaseId

        SET @Offset = @Offset + @Interval
        SET @Index = @Index + 1
	    FETCH NEXT FROM EventCursor INTO @EventId
    END
    
    CLOSE EventCursor
    DEALLOCATE EventCursor
    
    RETURN 0