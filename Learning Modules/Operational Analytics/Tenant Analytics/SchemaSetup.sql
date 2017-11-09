--Altering tables and views to include rowversion and customerEmailId as the id 

-- Create job to retrieve analytics that are distributed across all the tenants
EXEC jobs.sp_add_job
@job_name='ModifyTableViewTimestamp',
@description='Retrieve tickets data from all tenants',
@enabled=1,
@schedule_interval_type='Once'
--@schedule_interval_type='Minutes',
--@schedule_interval_count=15,
--@schedule_start_time='2017-08-21 10:00:00.0000000',
--@schedule_end_time='2017-08-21 11:00:00.0000000'


EXEC jobs.sp_add_jobstep
@job_name='ModifyTableViewTimestamp',
@command=N'
ALTER TABLE [dbo].[TicketPurchases]
ADD RowVersion rowversion
GO 
 
ALTER TABLE [dbo].[Events]
ADD RowVersion rowversion
GO 

ALTER TABLE [dbo].[Venue]
ADD RowVersion rowversion
GO

CREATE VIEW [dbo].[EventFacts] AS
SELECT      Convert(int, HASHBYTES(''md5'',v.VenueName)) AS VenueId, v.VenueName, v.VenueType,v.PostalCode as VenuePostalCode,  CountryCode AS VenueCountryCode,
            (SELECT SUM (SeatRows * SeatsPerRow) FROM [dbo].[Sections]) AS VenueCapacity,
            v.RowVersion AS VenueRowVersion,
            e.EventId, e.EventName, e.Subtitle AS EventSubtitle, e.Date AS EventDate,
            e.RowVersion AS EventRowVersion
FROM        [dbo].[Venue] as v
INNER JOIN [dbo].[Events] as e on 1=1
GO

DROP VIEW [dbo].[TicketFacts]
GO

CREATE VIEW [dbo].[TicketFacts] AS
SELECT      Convert(int, HASHBYTES(''md5'',v.VenueName)) AS VenueId, Convert(int, HASHBYTES(''md5'',c.Email)) AS CustomerEmailId, c.PostalCode AS CustomerPostalCode, c.CountryCode AS CustomerCountryCode,
            tp.TicketPurchaseId, tp.PurchaseDate, tp.PurchaseTotal, tp.RowVersion AS TicketPurchaseRowVersion,
            e.EventId, t.RowNumber, t.SeatNumber 
FROM        [dbo].[TicketPurchases] AS tp 
INNER JOIN [dbo].[Tickets] AS t ON t.TicketPurchaseId = tp.TicketPurchaseId 
INNER JOIN [dbo].[Events] AS e ON t.EventId = e.EventId 
INNER JOIN [dbo].[Customers] AS c ON tp.CustomerId = c.CustomerId
INNER join [dbo].[Venue] as v on 1=1
GO

IF (OBJECT_ID(''LastExtracted'')) IS NOT NULL DROP TABLE LastExtracted
CREATE TABLE [dbo].[LastExtracted]
(
    [LastExtractedVenueRowVersion]  VARBINARY(8) NOT NULL DEFAULT 0x0000000000000000,
    [LastExtractedEventRowVersion]  VARBINARY(8) NOT NULL DEFAULT 0x0000000000000000,
    [LastExtractedTicketRowVersion] VARBINARY(8) NOT NULL DEFAULT 0x0000000000000000,
    [Lock]                          CHAR NOT NULL DEFAULT ''X'',
    CONSTRAINT [CK_LastExtracted_Singleton] CHECK (Lock = ''X''),
    CONSTRAINT [PK_LastExtracted] PRIMARY KEY ([Lock])
)

INSERT INTO [dbo].[LastExtracted]
VALUES (0x0000000000000000, 0x0000000000000000, 0x0000000000000000, ''X'')

',
@credential_name='mydemocred',
@target_group_name='TenantGroup'


--
-- Views
-- Job and Job Execution Information and Status

--View all execution status
SELECT * FROM [jobs].[job_executions] 
WHERE job_name = 'ModifyTableViewTimestamp'

-- Cleanup
--EXEC [jobs].[sp_delete_job] 'ModifyTableViewTimestamp'
--EXEC jobs.sp_start_job 'ModifyTicketFactsView'