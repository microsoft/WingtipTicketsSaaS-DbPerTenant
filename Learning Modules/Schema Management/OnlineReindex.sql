-- Connect to and run against the jobaccount database
-- Create job to perform an online reindex after loading new reference data
EXEC jobs.sp_add_job
@job_name='Online Reindex PK__VenueTyp__265E44FD7FD4C885',
@description='Deploy new reference data',
@enabled=1,
@schedule_interval_type='Weeks',
@schedule_interval_count=1,
@schedule_start_time='2017-03-19 22:00:00.0000000'
GO

-- Create job step to perform an online reindex after loading new reference data
EXEC jobs.sp_add_jobstep
@job_name='Online Reindex PK__VenueTyp__265E44FD7FD4C885',
@command=N'
IF EXISTS (SELECT * FROM sys.indexes
           WHERE name = ''PK__VenueTyp__265E44FD7FD4C885'')
DBCC DBREINDEX (''VenueTypes'', PK__VenueTyp__265E44FD7FD4C885,80);
GO',
@credential_name='mydemocred',
@target_group_name='DemoServerGroup'

--
-- Views
-- Job and Job Execution Information and Status
--
select * from [jobs].[jobs] where job_name = 'Online Reindex PK__VenueTyp__265E44FD7FD4C885'
select * from [jobs].[jobsteps] where job_name = 'Online Reindex PK__VenueTyp__265E44FD7FD4C885'

WAITFOR DELAY '00:00:10'
--View parent execution status
select * from [jobs].[job_executions] where job_name = 'Online Reindex PK__VenueTyp__265E44FD7FD4C885' and step_id IS NULL

--View all execution status
select * from [jobs].[job_executions] where job_name = 'Online Reindex PK__VenueTyp__265E44FD7FD4C885'

--Stop a running job, requires active job_execution_id from [jobs].[job_executions] view
--EXEC [jobs].[sp_stop_job] '50ED03E8-AAC5-430B-ACF0-399468630620'

-- Cleanup
--EXEC [jobs].[sp_delete_job] 'Online Reindex PK__VenueTyp__265E44FD7FD4C885'