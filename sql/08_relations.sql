USE demo_proj;
GO

-- Related cards. Safe to re-run: the table is created once, and the two
-- customer seeds are updated in place. Other relation rows are left alone.
IF OBJECT_ID(N'dbo.api_card_children', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.api_card_children (
        id             int IDENTITY(1,1) NOT NULL CONSTRAINT pk_api_card_children PRIMARY KEY,
        parent         int            NOT NULL,
        child          int            NOT NULL,
        display_name   nvarchar(256)  NULL,
        keycode        nvarchar(64)   NULL,
        ref            nvarchar(128)  NULL,
        unbound        bit            NOT NULL CONSTRAINT df_card_child_unbound DEFAULT (0),
        reducer        nvarchar(max)  NULL,
        is_hidden      bit            NOT NULL CONSTRAINT df_card_child_hidden DEFAULT (0),
        action_order   int            NOT NULL CONSTRAINT df_card_child_order DEFAULT (10),
        CONSTRAINT fk_api_card_children_parent FOREIGN KEY (parent)
            REFERENCES dbo.api_card (id) ON DELETE CASCADE,
        CONSTRAINT fk_api_card_children_child FOREIGN KEY (child)
            REFERENCES dbo.api_card (id) ON DELETE NO ACTION,
        CONSTRAINT uq_api_card_children UNIQUE (parent, child, unbound)
    );
END
GO

DECLARE @customer int = (SELECT id FROM dbo.api_card WHERE name = N'customer');
DECLARE @note int = (SELECT id FROM dbo.api_card WHERE name = N'customer_note');

MERGE dbo.api_card_children AS t
USING (
    SELECT
        @customer AS parent,
        @note AS child,
        N'Notes' AS display_name,
        CAST(NULL AS nvarchar(64)) AS keycode,
        CAST(N'customer_id' AS nvarchar(128)) AS ref,
        CAST(0 AS bit) AS unbound,
        CAST(NULL AS nvarchar(max)) AS reducer,
        CAST(0 AS bit) AS is_hidden,
        10 AS action_order
    WHERE @customer IS NOT NULL AND @note IS NOT NULL
    UNION ALL
    SELECT
        @customer,
        @customer,
        N'Open customers',
        CAST(NULL AS nvarchar(64)),
        CAST(NULL AS nvarchar(128)),
        CAST(1 AS bit),
        CAST(N'status = N''open''' AS nvarchar(max)),
        CAST(0 AS bit),
        20
    WHERE @customer IS NOT NULL
) AS s
ON t.parent = s.parent AND t.child = s.child AND t.unbound = s.unbound
WHEN MATCHED THEN
    UPDATE SET
        display_name = s.display_name,
        keycode = s.keycode,
        ref = s.ref,
        reducer = s.reducer,
        is_hidden = s.is_hidden,
        action_order = s.action_order
WHEN NOT MATCHED BY TARGET THEN
    INSERT (parent, child, display_name, keycode, ref, unbound, reducer, is_hidden, action_order)
    VALUES (s.parent, s.child, s.display_name, s.keycode, s.ref, s.unbound, s.reducer, s.is_hidden, s.action_order);
GO
