CREATE PROCEDURE [dbo].[sp_DeleteVenue]
    @VenueId int = 0
AS
    IF @VenueId IS NULL
    BEGIN
        RAISERROR ('Error. @VenueId must be specified', 11, 1)
        RETURN 1
    END
        
    DELETE [dbo].[Tickets] WHERE VenueId = @VenueId
    
    DELETE [dbo].[TicketPurchases] WHERE VenueId = @VenueId
    
    DELETE [dbo].[Customers] WHERE VenueId = @VenueId
    
    DELETE [dbo].[EventSections] WHERE VenueId = @VenueId
    
    DELETE [dbo].[Sections] WHERE VenueId = @VenueId
    
    DELETE [dbo].[Events] WHERE VenueId = @VenueId
    
    DELETE [dbo].[Venues] WHERE VenueId = @VenueId

RETURN 0
