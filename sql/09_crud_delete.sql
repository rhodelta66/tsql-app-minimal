USE demo_proj;
GO

-- Sample business cards stay. NULL means delete is allowed, so deny it
-- only where the rule has not been set. IDE cards are left alone.
UPDATE dbo.api_card
SET crud_delete = N'1=0'
WHERE name IN (N'customer', N'customer_note')
  AND crud_delete IS NULL;
GO
