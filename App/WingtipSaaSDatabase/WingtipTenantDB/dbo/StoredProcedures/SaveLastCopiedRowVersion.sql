CREATE PROCEDURE [dbo].[SaveLastCopiedRowVersion]
(
    -- Add the parameters for the stored procedure here
    @tableName nvarchar(50),
    @trackerKey nvarchar(50),
    @lastCopiedValue varchar(25),
    @runId nvarchar(max),
    @runTimeStamp datetime
)
AS
BEGIN
    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON
	
	Declare @copiedValue VARBINARY(8)

	SELECT @copiedValue = CONVERT(VARBINARY(8), @lastCopiedValue, 1)

	INSERT INTO 
		[dbo].[CopyTracker]([TableName], [TrackerKey], [LastCopiedValue], [RunId], [RunTimeStamp]) 
	VALUES
		(@tableName, @trackerKey, @copiedValue, @runId, @runTimeStamp)
END
GO
