-- System-card flag. Safe to re-run. Does not drop a database or a card.
-- A table in the project database, dbo.main_db() plus _proj, is a system card.
-- A table in the business database is not. A name without a database is the
-- business database. Re-running applies that rule. It does not change ide_role.
-- The IDE form does not include this column.
USE demo_proj;
GO

IF COL_LENGTH(N'dbo.api_card', N'is_system') IS NULL
    ALTER TABLE dbo.api_card ADD is_system bit NOT NULL
        CONSTRAINT df_api_card_system DEFAULT (0);
GO

UPDATE dbo.api_card
SET is_system = CASE
        WHEN PARSENAME(tablename, 3) = dbo.main_db() + N'_proj' THEN 1
        ELSE 0
    END
WHERE is_system <> CASE
        WHEN PARSENAME(tablename, 3) = dbo.main_db() + N'_proj' THEN 1
        ELSE 0
    END;
GO
