-- Connect to and run against the jobaccount database in catalog-<User> server
-- Replace <User> below with your user name
DECLARE @User nvarchar(50);
DECLARE @server1 nvarchar(50);
DECLARE @server2 nvarchar(50);
SET @User = <'User'>;

-- Add a target group containing all tenant databases
EXEC [jobs].sp_add_target_group @target_group_name = 'TenantGroup'

-- Add a server target member, includes all databases in tenant server
SET @server1 = 'tenants1-dpt-' + @User + '.database.windows.net'

EXEC [jobs].sp_add_target_group_member
@target_group_name = 'TenantGroup',
@membership_type = 'Include',
@target_type = 'SqlServer',
@refresh_credential_name='myrefreshcred',
@server_name=@server1

-- Add a target group containing analytics store
EXEC [jobs].sp_add_target_group @target_group_name = 'AnalyticsGroup'

-- Add a server target member, includes only tenantanalytics database in catalog server
SET @server2 = 'catalog-dpt-' + @User + '.database.windows.net'

-- Doesn't required refresh credential because this target group only contains a single database
EXEC [jobs].sp_add_target_group_member
@target_group_name = 'AnalyticsGroup',
@target_type = 'Sqldatabase',
@membership_type = 'Include',
@server_name=@server2,
@database_name = 'tenantanalytics'

-- cleanup
--EXEC [jobs].[sp_delete_target_group] 'TenantGroup'
--EXEC [jobs].[sp_delete_target_group] 'AnalyticsGroup'
