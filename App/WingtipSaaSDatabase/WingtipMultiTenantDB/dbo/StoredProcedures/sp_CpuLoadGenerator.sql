---------------------------------------------------------------------------------------------------
-- sp_CpuLoadGenerator
--
-- Places a CPU-only load on the database. 
--
-- Duration and intensity (DTU level) of the load can be specified 
-- Although durations as low as 15 seconds are allowed, as the monitoring interval 
-- for databases is 15s, durations of 30s or more are recommended to ensure the 
-- DTU load is accurately reported in at least one interval. 
-- In the v-core model a single v-core is treated as 100 DTUs
-- 
-- NOTE: DTU-levels are only accurate with a Basic or Standard edition database, or a single vCore.
----------------------------------------------------------------------------------------------------
CREATE PROCEDURE [dbo].[sp_CpuLoadGenerator]
    @duration_seconds INT = 60, -- duration of burst
    @dtu_to_simulate INT = 50   -- DTU level of burst.  Between 0 and 100
AS
BEGIN   
    SET NOCOUNT ON; 

    IF (@duration_seconds < 15)
    BEGIN
        RAISERROR('Invalid parameter: @duration_seconds must be 15 or greater', 18, 0)
        RETURN
    END

    IF ((@dtu_to_simulate < 0) or (@dtu_to_simulate > 100))
    BEGIN
        RAISERROR('Invalid parameter: @dtu_to_simulate must be between 0 and 100', 18, 0)
        RETURN
    END

    DECLARE @outer_start DATETIME2(6) = CURRENT_TIMESTAMP;
    DECLARE @inner_start DATETIME2(6);
    DECLARE @run_for_ms INT = 15 * 1000 * 
        (SELECT TOP 1 
            CASE 
            WHEN (dtu_limit IS NOT NULL AND @dtu_to_simulate >= dtu_limit) THEN 1.0 
            WHEN (dtu_limit IS NOT NULL AND dtu_limit > 0 AND @dtu_to_simulate < dtu_limit) THEN (@dtu_to_simulate * 1.0 / dtu_limit) 
            WHEN (cpu_limit IS NOT NULL AND @dtu_to_simulate >= cpu_limit*100) THEN 1.0
            WHEN (cpu_limit IS NOT NULL AND cpu_limit > 0 AND @dtu_to_simulate < cpu_limit*100) THEN (@dtu_to_simulate * 1.0 / (100.0*cpu_limit))
            ELSE (@dtu_to_simulate * 1.0) END 
            FROM sys.dm_db_resource_stats ORDER BY end_time DESC);
    DECLARE @run_for_inverse VARCHAR(5) = CAST(15000-@run_for_ms AS VARCHAR(5));
    DECLARE @wait_for_str VARCHAR(12) = 
        CONCAT('00:00:',
                CASE 
                    WHEN LEN(@run_for_inverse) = 1 THEN CONCAT('00.00',@run_for_inverse)
                    WHEN LEN(@run_for_inverse) = 2 THEN CONCAT('00.0',@run_for_inverse)
                    WHEN LEN(@run_for_inverse) = 3 THEN CONCAT('00.',@run_for_inverse)
                    WHEN LEN(@run_for_inverse) = 4 THEN CONCAT('0',LEFT(@run_for_inverse,1), '.', RIGHT(@run_for_inverse,3))
                    WHEN LEN(@run_for_inverse) = 5 THEN CONCAT(LEFT(@run_for_inverse,2), '.', RIGHT(@run_for_inverse,3))
                END
               );

    DECLARE @f float;
    DECLARE @i INT = 1;

    WHILE (ABS(DATEDIFF(SECOND, CURRENT_TIMESTAMP, @outer_start)) < @duration_seconds)
    BEGIN
        SET @inner_start = CURRENT_TIMESTAMP;
        WHILE(ABS(DATEDIFF(MILLISECOND, CURRENT_TIMESTAMP, @inner_start)) <= @run_for_ms)
        BEGIN
            SET @f = (@i * 0.99999) + (@i * 0.9999) - (@i * 0.9999) + (@i * 0.999999) - (@i * 0.999999);
            SET @i = @i + 1;
        END
        WAITFOR DELAY @wait_for_str;
    END
    SET NOCOUNT OFF;

END
RETURN 0
