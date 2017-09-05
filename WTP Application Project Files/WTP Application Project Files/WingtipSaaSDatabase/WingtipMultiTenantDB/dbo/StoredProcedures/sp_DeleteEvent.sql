CREATE PROCEDURE [dbo].[sp_DeleteEvent]
	@VenueId int,
    @EventId int
AS
BEGIN
	SET NOCOUNT ON;

    DECLARE @Tickets int = (SELECT Count(*) FROM dbo.Tickets WHERE VenueId = @VenueId AND EventId = @EventId)

    IF @Tickets > 0
    BEGIN
        RAISERROR ('Error. Cannot delete event for which tickets have been purchased.', 11, 1)
        RETURN 1
    END

    DELETE FROM dbo.[EventSections]
    WHERE VenueId = @VenueId AND EventId = @EventId

    DELETE FROM dbo.[Events]
    WHERE VenueId = @VenueId AND EventId = @EventId

    RETURN 0
END