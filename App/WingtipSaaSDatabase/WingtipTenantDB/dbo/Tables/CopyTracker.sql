CREATE TABLE [dbo].[CopyTracker](
	[Id] [bigint] IDENTITY(1,1) NOT NULL,
	[TableName] [nvarchar](max) NOT NULL,
	[TrackerKey] [nvarchar](max) NOT NULL,
	[LastCopiedValue] [varbinary](8) NOT NULL,
	[RunId] [nvarchar](max) NULL,
	[RunTimeStamp] [datetime] NULL
)
GO