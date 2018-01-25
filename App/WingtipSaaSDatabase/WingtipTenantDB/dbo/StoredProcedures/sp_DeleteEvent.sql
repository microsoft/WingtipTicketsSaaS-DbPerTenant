CREATE PROCEDURE [dbo].[sp_DeleteEvent]
	@EventId int
AS
BEGIN
	SET NOCOUNT ON;

    DECLARE @Tickets int = (SELECT Count(*) FROM dbo.Tickets WHERE EventId = @EventId)

    IF @Tickets > 0
    BEGIN
        RAISERROR ('Error. Cannot delete events for which tickets have been purchased.', 11, 1)
        RETURN 1
    END

    DELETE FROM dbo.[EventSections]
    WHERE EventId = @EventId

    DELETE FROM dbo.[Events]
    WHERE EventId = @EventId

    RETURN 0
END