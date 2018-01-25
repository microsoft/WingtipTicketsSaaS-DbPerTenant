CREATE PROCEDURE [dbo].[sp_ResetEventDates]
    @StartHour int = 19,
    @StartMinute int = 00
AS
    SET NOCOUNT ON

    DECLARE @VenueId int
    DECLARE @EventId int
    DECLARE @Offset int   
    DECLARE @Interval int = 3   -- interval in days between each event
    DECLARE @OldEventDate datetime
    DECLARE @NewEventDate datetime
    DECLARE @Diff int
    DECLARE @BaseDate datetime = DATETIMEFROMPARTS(YEAR(CURRENT_TIMESTAMP),MONTH(CURRENT_TIMESTAMP),DAY(CURRENT_TIMESTAMP),@StartHour,@StartMinute,00,000)
    DECLARE VenueCursor CURSOR FOR SELECT VenueId FROM [dbo].[Venues]

    OPEN VenueCursor
    FETCH NEXT FROM VenueCursor INTO @VenueId 

    WHILE @@Fetch_Status = 0
    BEGIN
        SET @Offset = -5    -- offset of the first event in days from current date 
        DECLARE EventCursor CURSOR FOR SELECT EventId FROM [dbo].[Events] WHERE VenueId = @VenueId 
        OPEN EventCursor
        FETCH NEXT FROM EventCursor INTO @EventId
        --
        WHILE @@Fetch_Status = 0
        BEGIN
            SET @OldEventDate = (SELECT top 1 [Date] from [Events] WHERE VenueId = @VenueId AND EventId=@EventId)
            SET @NewEventDate = DATEADD(Day,@Offset,@BaseDate)
        
            UPDATE [Events] SET [Date] = @NewEventDate WHERE VenueId = @VenueId AND EventId=@EventId 
        
            UPDATE TicketPurchases SET PurchaseDate = DATEADD(day,Diff,@NewEventDate) 
            FROM TicketPurchases AS tp
            INNER JOIN (SELECT tp2.TicketPurchaseId, DATEDIFF(day,@OldEventDate,tp2.PurchaseDate) AS Diff 
                            FROM TicketPurchases AS tp2
                            INNER JOIN [Tickets] AS t ON t.TicketPurchaseId = tp2.TicketPurchaseId
                            INNER JOIN [Events] AS e ON t.EventId = e.EventId
                        WHERE e.VenueId = @VenueId AND e.EventId = @EventId) AS etp ON etp.TicketPurchaseId = tp.TicketPurchaseId

            SET @Offset = @Offset + @Interval
            --get next event
	        FETCH NEXT FROM EventCursor INTO @EventId

        END    
        CLOSE EventCursor
        DEALLOCATE EventCursor
        -- get next venue 
        FETCH NEXT FROM VenueCursor INTO @VenueId
                
    END

    CLOSE VenueCursor
    DEALLOCATE VenueCursor
    RETURN 0