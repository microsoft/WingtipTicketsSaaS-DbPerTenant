-- Connect to and run against the jobaccount database in catalog-<WtpUser> server
-- Replace <WtpUser> below with your user name
DECLARE @WtpUser nvarchar(50);
DECLARE @server1 nvarchar(50);
DECLARE @server2 nvarchar(50);
SET @WtpUser = '<WtpUser>';

-- Add a target group containing server(s)
EXEC [jobs].sp_add_target_group @target_group_name = 'DemoServerGroup'

-- Add a server target member, includes all databases in tenant server
SET @server1 = 'customers1-' + @WtpUser + '.database.windows.net'

EXEC [jobs].sp_add_target_group_member
@target_group_name =  'DemoServerGroup',
@membership_type = 'Include',
@target_type = 'SqlServer',
@refresh_credential_name='myrefreshcred',
@server_name=@server1

-- Add the database target member of the 'golden' database and analysis database
SET @server2 = 'catalog-' + @WtpUser + '.database.windows.net'

EXEC [jobs].sp_add_target_group_member
@target_group_name =  'DemoServerGroup',
@membership_type = 'Include',
@target_type = 'SqlDatabase',
@server_name=@server2,
@database_name='baseTenantDB'

EXEC [jobs].sp_add_target_group_member
@target_group_name =  'DemoServerGroup',
@membership_type = 'Include',
@target_type = 'SqlDatabase',
@server_name=@server2,
@database_name='adhocanalytics'

-- Add a job to deploy new reference data
EXEC jobs.sp_add_job
@job_name='Reference Data Deployment',
@description='Deploy new reference data',
@enabled=1,
@schedule_interval_type='Once'
GO

-- Add a job step to extend the set of VenueTypes using an idempotent MERGE script
EXEC jobs.sp_add_jobstep
@job_name='Reference Data Deployment',
@command=N'
MERGE INTO [dbo].[VenueTypes] AS [target]
USING (VALUES
    (''MultiPurposeVenue'',''Multi Purpose Venue'',''Event'', ''Event'',''Events'',''en-us''),
    (''ClassicalConcertHall'',''Classical Concert Hall'',''Classical Concert'',''Concert'',''Concerts'',''en-us''),
    (''JazzClub'',''Jazz Club'',''Jazz Session'',''Session'',''Sessions'',''en-us''),
    (''JudoClub'',''Judo Club'',''Judo Tournament'',''Tournament'',''Tournaments'',''en-us''),
    (''SoccerClub'',''Soccer Club'',''Soccer Match'', ''Match'',''Matches'',''en-us''),
    (''MotorRacing'',''Motor Racing'',''Car Race'', ''Race'',''Races'',''en-us''),
    (''DanceStudio'', ''Dance Studio'', ''Performance'', ''Performance'', ''Performances'',''en-us''),
    (''BluesClub'', ''Blues Club'', ''Blues Session'', ''Session'',''Sessions'',''en-us'' ),
    (''RockMusicVenue'',''Rock Music Venue'',''Rock Concert'',''Concert'', ''Concerts'',''en-us''),
    (''Opera'',''Opera'',''Opera'',''Opera'',''Operas'',''en-us''),
    (''MotorCycleRacing'',''Motorcycle Racing'',''Motorcycle Race'', ''Race'', ''Races'', ''en-us''), -- NEW
    (''SwimmingClub'',''Swimming Club'',''Swimming Race'',''Race'',''Races'',''en-us'') -- NEW
) AS source(
    VenueType,VenueTypeName,EventTypeName,EventTypeShortName,EventTypeShortNamePlural,[Language]
)              
ON [target].VenueType = source.VenueType
-- update existing rows
WHEN MATCHED THEN
    UPDATE SET 
        VenueTypeName = source.VenueTypeName,
        EventTypeName = source.EventTypeName,
        EventTypeShortName = source.EventTypeShortName,
        EventTypeShortNamePlural = source.EventTypeShortNamePlural,
        [Language] = source.[Language]
-- insert new rows
WHEN NOT MATCHED BY TARGET THEN
    INSERT (VenueType,VenueTypeName,EventTypeName,EventTypeShortName,EventTypeShortNamePlural,[Language])
    VALUES (VenueType,VenueTypeName,EventTypeName,EventTypeShortName,EventTypeShortNamePlural,[Language])
;
GO',
@credential_name='mydemocred',
@target_group_name='DemoServerGroup'

--
-- Views
-- Job and Job Execution Information and Status
--
SELECT * FROM [jobs].[jobs] WHERE job_name = 'Reference Data Deployment'
SELECT * FROM [jobs].[jobsteps] WHERE job_name = 'Reference Data Deployment'

WAITFOR DELAY '00:00:10'
--View parent execution status
SELECT * FROM [jobs].[job_executions] 
WHERE job_name = 'Reference Data Deployment' and step_id IS NULL

--View all execution status
SELECT * FROM [jobs].[job_executions] 
WHERE job_name = 'Reference Data Deployment'

--Stop the job execution, requires active job_execution_id from [jobs].[job_executions] view
--EXEC [jobs].[sp_stop_job] '9B0FB896-CA10-44B0-8D9E-51149D925DB2'

-- Cleanup
--EXEC [jobs].[sp_delete_job] 'Reference Data Deployment'
--EXEC [jobs].[sp_delete_target_group] 'DemoServerGroup'