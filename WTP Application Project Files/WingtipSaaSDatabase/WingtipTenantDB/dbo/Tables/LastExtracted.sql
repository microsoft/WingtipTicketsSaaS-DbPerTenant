CREATE TABLE [dbo].[LastExtracted]
(
	[LastExtractedVenueRowVersion]  VARBINARY(8) NOT NULL DEFAULT 0x0000000000000000,
	[LastExtractedEventRowVersion]  VARBINARY(8) NOT NULL DEFAULT 0x0000000000000000,
	[LastExtractedTicketRowVersion] VARBINARY(8) NOT NULL DEFAULT 0x0000000000000000,
	[Lock]                          CHAR NOT NULL DEFAULT 'X',
	CONSTRAINT [CK_LastExtracted_Singleton] CHECK (Lock = 'X'),
	CONSTRAINT [PK_LastExtracted] PRIMARY KEY ([Lock])

)
