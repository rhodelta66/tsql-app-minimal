-- Metadata-write gate. Safe to re-run. Does not drop a database or a card.
-- NULL ide_role means this gate does not apply. A value is the comma-separated
-- roles that may save or delete a row when that card's basetable is api_card,
-- api_card_fields, or api_card_actions. Opening the card stays allowed.
-- The IDE form does not include the column, so a save of card ide cannot clear it.
USE demo_proj;
GO

IF COL_LENGTH(N'dbo.api_card', N'ide_role') IS NULL
    ALTER TABLE dbo.api_card ADD ide_role nvarchar(128) NULL;
GO

UPDATE dbo.api_card
SET ide_role = N'admin'
WHERE name = N'ide_action'
  AND NULLIF(LTRIM(RTRIM(ide_role)), N'') IS NULL;
GO
