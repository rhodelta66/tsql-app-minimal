USE demo_proj;
GO

-- Writes posted form values into the card base table, or deletes one row.
-- Column names and types come from metadata and sys.columns. Values stay in
-- parameters. A field with its own sql expression is not writable.
-- A three-part tablename may name this database or the main database.
-- Any other database is rejected. A write to api_card or api_card_fields
-- in this database rebuilds that card cache. A delete of api_card_fields
-- rebuilds the card that owned the field. Action sql is not cached.
CREATE OR ALTER PROCEDURE dbo.sp_api_card_save
    @card_id     int,
    @id          nvarchar(128),
    @is_new      bit,
    @values_json nvarchar(max),
    @new_id      nvarchar(128) OUTPUT,
    @error       nvarchar(400) OUTPUT,
    @delete      bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET @new_id = NULL;
    SET @error = NULL;

    DECLARE @basetable nvarchar(256);
    DECLARE @id_column nvarchar(128);
    DECLARE @gate nvarchar(max);
    DECLARE @tablename nvarchar(256);
    DECLARE @named_db nvarchar(128);
    DECLARE @main nvarchar(128) = dbo.main_db();
    DECLARE @rebuild_id int;
    DECLARE @cache_toast bit;

    SELECT
        @basetable = c.basetable,
        @id_column = c.id_column,
        @tablename = c.tablename,
        @gate = CASE
            WHEN ISNULL(@delete, 0) = 1 THEN c.crud_delete
            WHEN ISNULL(@is_new, 0) = 1 THEN c.crud_create
            ELSE c.crud_update
        END
    FROM dbo.api_card AS c
    WHERE c.id = @card_id;

    -- No database part keeps the main database, so customer still writes demo.
    SET @named_db = PARSENAME(@tablename, 3);
    IF @named_db IS NOT NULL AND @named_db <> DB_NAME() AND @named_db <> @main
    BEGIN
        SET @error = N'This card cannot be saved.';
        RETURN;
    END
    IF @named_db IS NOT NULL
        SET @main = @named_db;

    IF @basetable IS NULL OR @id_column IS NULL OR @main IS NULL
       OR @main LIKE N'%[^A-Za-z0-9_]%' OR @main LIKE N'[0-9]%'
       OR @basetable LIKE N'%[^A-Za-z0-9_]%' OR @basetable LIKE N'[0-9]%'
       OR @id_column LIKE N'%[^A-Za-z0-9_]%' OR @id_column LIKE N'[0-9]%'
    BEGIN
        SET @error = N'This card cannot be saved.';
        RETURN;
    END

    IF @gate IS NOT NULL AND LTRIM(RTRIM(@gate)) <> N''
    BEGIN
        IF @gate LIKE N'%;%' OR @gate LIKE N'%--%' OR @gate LIKE N'%/*%'
        BEGIN
            SET @error = N'The save rule is not a single expression.';
            RETURN;
        END
        DECLARE @allowed bit = 0;
        BEGIN TRY
            DECLARE @gate_sql nvarchar(max) = N'SELECT @allowed = CASE WHEN (' + @gate + N') THEN 1 ELSE 0 END;';
            EXEC sp_executesql @gate_sql, N'@allowed bit OUTPUT', @allowed = @allowed OUTPUT;
        END TRY
        BEGIN CATCH
            SET @error = N'The save rule failed.';
            RETURN;
        END CATCH
        IF @allowed = 0
        BEGIN
            SET @error = CASE
                WHEN ISNULL(@delete, 0) = 1 THEN N'Delete is not allowed for this card.'
                WHEN ISNULL(@is_new, 0) = 1 THEN N'Create is not allowed for this card.'
                ELSE N'Update is not allowed for this card.'
            END;
            RETURN;
        END
    END

    IF ISNULL(@delete, 0) = 1
    BEGIN
        IF @id IS NULL OR LTRIM(RTRIM(@id)) = N''
        BEGIN
            SET @error = N'Choose a record to delete.';
            RETURN;
        END

        DECLARE @delete_decl nvarchar(128);
        DECLARE @delete_type_sql nvarchar(max) = N'
            SELECT @decl = CASE
                WHEN ty.name IN (N''decimal'', N''numeric'')
                    THEN ty.name + N''('' + CONVERT(nvarchar(10), c.precision) + N'','' + CONVERT(nvarchar(10), c.scale) + N'')''
                WHEN ty.name IN (N''nvarchar'', N''nchar'')
                    THEN ty.name + N''('' + CASE WHEN c.max_length < 0 THEN N''max'' ELSE CONVERT(nvarchar(10), c.max_length / 2) END + N'')''
                WHEN ty.name IN (N''varchar'', N''char'', N''varbinary'', N''binary'')
                    THEN ty.name + N''('' + CASE WHEN c.max_length < 0 THEN N''max'' ELSE CONVERT(nvarchar(10), c.max_length) END + N'')''
                WHEN ty.name IN (N''datetime2'', N''time'', N''datetimeoffset'')
                    THEN ty.name + N''('' + CONVERT(nvarchar(10), c.scale) + N'')''
                ELSE ty.name
            END
            FROM ' + QUOTENAME(@main) + N'.sys.columns AS c
            INNER JOIN ' + QUOTENAME(@main) + N'.sys.types AS ty
                ON ty.user_type_id = c.user_type_id
            INNER JOIN ' + QUOTENAME(@main) + N'.sys.tables AS t
                ON t.object_id = c.object_id
            INNER JOIN ' + QUOTENAME(@main) + N'.sys.schemas AS s
                ON s.schema_id = t.schema_id
            WHERE s.name = N''dbo''
              AND t.name = @table
              AND c.name = @column;';
        EXEC sp_executesql
            @delete_type_sql,
            N'@table nvarchar(128), @column nvarchar(128), @decl nvarchar(128) OUTPUT',
            @table = @basetable,
            @column = @id_column,
            @decl = @delete_decl OUTPUT;

        IF @delete_decl IS NULL
           OR @delete_decl LIKE N'%[^A-Za-z0-9_,()]%'
           OR @delete_decl LIKE N'%--%'
        BEGIN
            SET @error = N'This card cannot be saved.';
            RETURN;
        END

        -- Read the owning card before the row is gone. Action sql is read live.
        IF @main = DB_NAME() AND @basetable = N'api_card_fields'
            SELECT @rebuild_id = f.card_id
            FROM dbo.api_card_fields AS f
            WHERE f.id = TRY_CONVERT(int, @id);

        DECLARE @delete_sql nvarchar(max) = N'
            DELETE FROM ' + QUOTENAME(@main) + N'.dbo.' + QUOTENAME(@basetable) + N'
            WHERE ' + QUOTENAME(@id_column) + N' = TRY_CONVERT(' + @delete_decl + N', @id);
            SET @n = @@ROWCOUNT;';
        DECLARE @deleted int = 0;
        BEGIN TRY
            EXEC sp_executesql
                @delete_sql,
                N'@id nvarchar(128), @n int OUTPUT',
                @id = @id,
                @n = @deleted OUTPUT;
        END TRY
        BEGIN CATCH
            SET @error = LEFT(ERROR_MESSAGE(), 400);
            RETURN;
        END CATCH

        IF @deleted = 0
        BEGIN
            SET @error = N'Record was not found.';
            RETURN;
        END

        IF @rebuild_id IS NOT NULL
           AND EXISTS (
                SELECT 1
                FROM dbo.api_card AS c
                WHERE c.id = @rebuild_id
                  AND NULLIF(LTRIM(RTRIM(c.id_column)), N'') IS NOT NULL
                  AND NULLIF(LTRIM(RTRIM(c.tablename)), N'') IS NOT NULL
           )
        BEGIN
            SET @cache_toast = 0;
            BEGIN TRY
                EXEC dbo.sp_api_card_create_cache
                    @card_id = @rebuild_id,
                    @toast = @cache_toast;
            END TRY
            BEGIN CATCH
                SET @error = LEFT(ERROR_MESSAGE(), 400);
            END CATCH
        END
        RETURN;
    END

    IF @values_json IS NULL OR ISJSON(@values_json) <> 1 OR LEFT(LTRIM(@values_json), 1) <> N'{'
    BEGIN
        SET @error = N'Save values are not an object.';
        RETURN;
    END

    DECLARE @cols TABLE (
        name        nvarchar(128) NOT NULL PRIMARY KEY,
        type_name   nvarchar(128) NOT NULL,
        type_decl   nvarchar(128) NOT NULL,
        is_nullable bit           NOT NULL,
        is_identity bit           NOT NULL,
        expr        nvarchar(800) NULL
    );

    DECLARE @load nvarchar(max) = N'
        SELECT c.name, ty.name,
            CASE
                WHEN ty.name IN (N''decimal'', N''numeric'')
                    THEN ty.name + N''('' + CONVERT(nvarchar(10), c.precision) + N'','' + CONVERT(nvarchar(10), c.scale) + N'')''
                WHEN ty.name IN (N''nvarchar'', N''nchar'')
                    THEN ty.name + N''('' + CASE WHEN c.max_length < 0 THEN N''max'' ELSE CONVERT(nvarchar(10), c.max_length / 2) END + N'')''
                WHEN ty.name IN (N''varchar'', N''char'')
                    THEN ty.name + N''('' + CASE WHEN c.max_length < 0 THEN N''max'' ELSE CONVERT(nvarchar(10), c.max_length) END + N'')''
                WHEN ty.name IN (N''datetime2'', N''time'', N''datetimeoffset'')
                    THEN ty.name + N''('' + CONVERT(nvarchar(10), c.scale) + N'')''
                ELSE ty.name
            END,
            c.is_nullable, c.is_identity
        FROM ' + QUOTENAME(@main) + N'.sys.columns AS c
        INNER JOIN ' + QUOTENAME(@main) + N'.sys.types AS ty
            ON ty.user_type_id = c.user_type_id
        INNER JOIN ' + QUOTENAME(@main) + N'.sys.tables AS t
            ON t.object_id = c.object_id
        INNER JOIN ' + QUOTENAME(@main) + N'.sys.schemas AS s
            ON s.schema_id = t.schema_id
        WHERE s.name = N''dbo''
          AND t.name = @table
          AND c.is_computed = 0
          AND c.name NOT LIKE N''%[^A-Za-z0-9_]%''';

    INSERT INTO @cols (name, type_name, type_decl, is_nullable, is_identity)
    EXEC sp_executesql @load, N'@table nvarchar(128)', @table = @basetable;

    DECLARE @id_decl nvarchar(128);
    SELECT @id_decl = type_decl FROM @cols WHERE name = @id_column;
    IF @id_decl IS NULL
    BEGIN
        SET @error = N'This card cannot be saved.';
        RETURN;
    END

    DELETE c
    FROM @cols AS c
    WHERE c.name = @id_column
       OR c.is_identity = 1
       OR NOT EXISTS (
            SELECT 1
            FROM dbo.api_card_fields AS f
            WHERE f.card_id = @card_id
              AND f.name = c.name
              AND ISNULL(f.detail_order, 0) > 0
              AND NULLIF(LTRIM(RTRIM(f.sql)), N'') IS NULL
       );

    IF NOT EXISTS (SELECT 1 FROM @cols)
    BEGIN
        SET @error = N'This card has no editable fields.';
        RETURN;
    END

    DECLARE @bad nvarchar(128);
    SELECT TOP (1) @bad = c.name
    FROM @cols AS c
    LEFT JOIN OPENJSON(@values_json) AS j ON j.[key] COLLATE DATABASE_DEFAULT = c.name
    WHERE (c.is_nullable = 0 AND NULLIF(j.[value], N'') IS NULL)
       OR (
            NULLIF(j.[value], N'') IS NOT NULL
            AND (
                (c.type_name IN (N'int', N'bigint', N'smallint', N'tinyint') AND TRY_CONVERT(bigint, j.[value]) IS NULL)
                OR (c.type_name IN (N'decimal', N'numeric', N'float', N'real', N'money', N'smallmoney') AND TRY_CONVERT(decimal(38, 10), j.[value]) IS NULL)
                OR (c.type_name = N'bit' AND LOWER(j.[value] COLLATE DATABASE_DEFAULT) NOT IN (N'0', N'1', N'true', N'false'))
                OR (c.type_name = N'date' AND TRY_CONVERT(date, j.[value]) IS NULL)
                OR (c.type_name IN (N'datetime', N'datetime2') AND TRY_CONVERT(datetime2, j.[value]) IS NULL)
            )
       )
    ORDER BY c.name;
    IF @bad IS NOT NULL
    BEGIN
        SET @error = @bad + N' is missing or not valid.';
        RETURN;
    END

    IF ISNULL(@is_new, 0) = 0 AND (@id IS NULL OR LTRIM(RTRIM(@id)) = N'')
    BEGIN
        SET @error = N'Choose a record to update.';
        RETURN;
    END

    UPDATE c
    SET expr = CASE
        WHEN c.type_name = N'bit' THEN
            N'CASE LOWER(MAX(CASE WHEN [key] COLLATE DATABASE_DEFAULT = N''' + c.name + N''' THEN [value] END))'
            + N' WHEN N''1'' THEN CONVERT(bit, 1) WHEN N''true'' THEN CONVERT(bit, 1)'
            + N' WHEN N''0'' THEN CONVERT(bit, 0) WHEN N''false'' THEN CONVERT(bit, 0) ELSE NULL END'
        WHEN c.type_name IN (
            N'int', N'bigint', N'smallint', N'tinyint',
            N'decimal', N'numeric', N'float', N'real', N'money', N'smallmoney',
            N'date', N'datetime', N'datetime2', N'time'
        ) THEN
            N'TRY_CONVERT(' + c.type_decl + N', NULLIF(MAX(CASE WHEN [key] COLLATE DATABASE_DEFAULT = N''' + c.name + N''' THEN [value] END), N''''))'
        ELSE
            N'NULLIF(MAX(CASE WHEN [key] COLLATE DATABASE_DEFAULT = N''' + c.name + N''' THEN [value] END), N'''')'
    END
    FROM @cols AS c;

    DECLARE @insert_cols nvarchar(max);
    DECLARE @select_list nvarchar(max);
    DECLARE @set_list nvarchar(max);
    SELECT
        @insert_cols = STRING_AGG(CAST(QUOTENAME(c.name) AS nvarchar(max)), N', ') WITHIN GROUP (ORDER BY c.name),
        @select_list = STRING_AGG(CAST(c.expr + N' AS ' + QUOTENAME(c.name) AS nvarchar(max)), N', ') WITHIN GROUP (ORDER BY c.name),
        @set_list = STRING_AGG(CAST(QUOTENAME(c.name) + N' = src.' + QUOTENAME(c.name) AS nvarchar(max)), N', ') WITHIN GROUP (ORDER BY c.name)
    FROM @cols AS c;

    DECLARE @sql nvarchar(max);
    IF ISNULL(@is_new, 0) = 1
        SET @sql = N'
            DECLARE @out TABLE (id sql_variant);
            INSERT INTO ' + QUOTENAME(@main) + N'.dbo.' + QUOTENAME(@basetable) + N' (' + @insert_cols + N')
            OUTPUT INSERTED.' + QUOTENAME(@id_column) + N' INTO @out (id)
            SELECT ' + @select_list + N'
            FROM OPENJSON(@values);
            SET @n = @@ROWCOUNT;
            SELECT @new_id = CONVERT(nvarchar(128), id) FROM @out;';
    ELSE
        SET @sql = N'
            UPDATE t
            SET ' + @set_list + N'
            FROM ' + QUOTENAME(@main) + N'.dbo.' + QUOTENAME(@basetable) + N' AS t
            CROSS JOIN (
                SELECT ' + @select_list + N'
                FROM OPENJSON(@values)
            ) AS src
            WHERE t.' + QUOTENAME(@id_column) + N' = TRY_CONVERT(' + @id_decl + N', @id);
            SET @n = @@ROWCOUNT;
            SET @new_id = @id;';

    DECLARE @n int = 0;
    BEGIN TRY
        EXEC sp_executesql
            @sql,
            N'@values nvarchar(max), @id nvarchar(128), @new_id nvarchar(128) OUTPUT, @n int OUTPUT',
            @values = @values_json,
            @id = @id,
            @new_id = @new_id OUTPUT,
            @n = @n OUTPUT;
    END TRY
    BEGIN CATCH
        SET @error = LEFT(ERROR_MESSAGE(), 400);
        RETURN;
    END CATCH

    IF ISNULL(@is_new, 0) = 1 AND (@new_id IS NULL OR @n = 0)
        SET @error = N'The row was not created.';
    ELSE IF ISNULL(@is_new, 0) = 0 AND @n = 0
        SET @error = N'Record was not found.';

    -- The row is already written. A cache failure is reported instead of Saved.
    -- Skip a card that has no id or table, because create_cache would throw.
    IF @error IS NULL
       AND @main = DB_NAME()
       AND @basetable IN (N'api_card', N'api_card_fields')
    BEGIN
        SET @rebuild_id = NULL;
        IF @basetable = N'api_card'
            SET @rebuild_id = TRY_CONVERT(int, @new_id);
        ELSE
            SELECT @rebuild_id = f.card_id
            FROM dbo.api_card_fields AS f
            WHERE f.id = TRY_CONVERT(int, @new_id);

        IF @rebuild_id IS NOT NULL
           AND EXISTS (
                SELECT 1
                FROM dbo.api_card AS c
                WHERE c.id = @rebuild_id
                  AND NULLIF(LTRIM(RTRIM(c.id_column)), N'') IS NOT NULL
                  AND NULLIF(LTRIM(RTRIM(c.tablename)), N'') IS NOT NULL
           )
        BEGIN
            SET @cache_toast = 0;
            BEGIN TRY
                EXEC dbo.sp_api_card_create_cache
                    @card_id = @rebuild_id,
                    @toast = @cache_toast;
            END TRY
            BEGIN CATCH
                SET @error = LEFT(ERROR_MESSAGE(), 400);
            END CATCH
        END
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_request
    @session_token nvarchar(64) = NULL,
    @pathname      nvarchar(400) = N'/',
    @posted_json   nvarchar(max) = NULL,
    @action        nvarchar(128) = NULL,
    @id            nvarchar(max) = NULL,
    @ids           nvarchar(max) = NULL,
    @close         bit = 0,
    @caller_email  nvarchar(256) = NULL,
    @caller_sub    nvarchar(256) = NULL,
    @save          bit = 0,
    @values_json   nvarchar(max) = NULL,
    @delete        bit = 0,
    @caller_roles  nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF OBJECT_ID(N'tempdb..#coltype') IS NOT NULL
        DROP TABLE #coltype;
    CREATE TABLE #coltype (
        name nvarchar(128) NOT NULL PRIMARY KEY,
        typ  nvarchar(128) NOT NULL
    );

    DECLARE @sid int;
    DECLARE @user_name nvarchar(256);
    DECLARE @user_id int;
    DECLARE @main_db nvarchar(128) = dbo.main_db();
    DECLARE @error nvarchar(4000) = NULL;
    DECLARE @cleared bit = 0;

    IF @session_token IS NULL OR LTRIM(RTRIM(@session_token)) = N''
        SET @session_token = CONVERT(nvarchar(64), NEWID());

    SELECT
        @sid = s.id,
        @user_name = s.user_name,
        @user_id = s.user_id
    FROM dbo.api_session AS s
    WHERE s.token = @session_token;

    IF @caller_email IS NOT NULL AND LTRIM(RTRIM(@caller_email)) <> N''
        SET @caller_email = LEFT(LTRIM(RTRIM(@caller_email)), 256);
    ELSE
        SET @caller_email = NULL;

    IF @sid IS NULL
    BEGIN
        SET @user_name = COALESCE(@caller_email, N'dev@local');
        SET @user_id = 1;
        INSERT INTO dbo.api_session (token, user_name, user_id)
        VALUES (@session_token, @user_name, @user_id);
        SET @sid = SCOPE_IDENTITY();
    END
    ELSE IF @caller_email IS NOT NULL
    BEGIN
        SET @user_name = @caller_email;
        UPDATE dbo.api_session SET user_name = @user_name WHERE id = @sid;
    END

    -- Role names from the verified token. The request body cannot set this.
    DECLARE @role_hold TABLE (
        name nvarchar(128) NOT NULL PRIMARY KEY
    );
    IF @caller_roles IS NOT NULL AND ISJSON(@caller_roles) = 1
    BEGIN
        INSERT INTO @role_hold (name)
        SELECT DISTINCT LEFT(LTRIM(RTRIM(j.value)), 128)
        FROM OPENJSON(@caller_roles) AS j
        WHERE j.[type] = 1
          AND LTRIM(RTRIM(j.value)) <> N'';
    END

    DECLARE @raw nvarchar(400) = ISNULL(@pathname, N'/');
    DECLARE @qmark int = CHARINDEX(N'?', @raw);
    IF @qmark > 0
        SET @raw = LEFT(@raw, @qmark - 1);
    WHILE LEFT(@raw, 1) = N'/'
        SET @raw = SUBSTRING(@raw, 2, 400);
    WHILE RIGHT(@raw, 1) = N'/' AND LEN(@raw) > 0
        SET @raw = LEFT(@raw, LEN(@raw) - 1);

    -- /card, /card/id, /parent/id/child, /parent/id/child/record.
    -- A third segment is the child card, not more of the parent record id.
    DECLARE @segs TABLE (
        n     int           NOT NULL PRIMARY KEY,
        token nvarchar(128) NOT NULL
    );
    DECLARE @rest nvarchar(400) = @raw;
    DECLARE @seg_n int = 0;
    DECLARE @cut int;
    WHILE @rest <> N'' AND @seg_n < 4
    BEGIN
        SET @seg_n += 1;
        SET @cut = CHARINDEX(N'/', @rest);
        IF @cut = 0
        BEGIN
            INSERT INTO @segs (n, token) VALUES (@seg_n, LEFT(@rest, 128));
            SET @rest = N'';
        END
        ELSE
        BEGIN
            INSERT INTO @segs (n, token) VALUES (@seg_n, LEFT(LEFT(@rest, @cut - 1), 128));
            SET @rest = SUBSTRING(@rest, @cut + 1, 400);
        END
    END

    DECLARE @seg1 nvarchar(128);
    DECLARE @seg2 nvarchar(128);
    DECLARE @seg3 nvarchar(128);
    DECLARE @seg4 nvarchar(128);
    SELECT @seg1 = token FROM @segs WHERE n = 1;
    SELECT @seg2 = token FROM @segs WHERE n = 2;
    SELECT @seg3 = token FROM @segs WHERE n = 3;
    SELECT @seg4 = token FROM @segs WHERE n = 4;

    DECLARE @parent_card_name nvarchar(128) = NULL;
    DECLARE @parent_record nvarchar(128) = NULL;
    DECLARE @in_child bit = 0;
    DECLARE @card_token nvarchar(128);
    DECLARE @record_token nvarchar(128);
    IF @seg3 IS NOT NULL AND @seg3 <> N''
    BEGIN
        SET @in_child = 1;
        SET @parent_card_name = NULLIF(@seg1, N'');
        SET @parent_record = NULLIF(@seg2, N'');
        SET @card_token = @seg3;
        SET @record_token = NULLIF(@seg4, N'');
    END
    ELSE
    BEGIN
        SET @card_token = NULLIF(@seg1, N'');
        SET @record_token = NULLIF(@seg2, N'');
    END

    DECLARE @norm nvarchar(400);
    DECLARE @is_form bit = 0;
    DECLARE @is_new bit = 0;
    IF @in_child = 1
    BEGIN
        SET @norm = N'/' + @parent_card_name + N'/' + ISNULL(@parent_record, N'') + N'/' + @card_token;
        IF @record_token IS NOT NULL
        BEGIN
            SET @norm = @norm + N'/' + @record_token;
            SET @is_form = 1;
            IF LOWER(@record_token) = N'new'
                SET @is_new = 1;
        END
    END
    ELSE IF @card_token IS NULL OR @card_token = N''
        SET @norm = N'/';
    ELSE IF @record_token IS NULL OR @record_token = N''
        SET @norm = N'/' + @card_token;
    ELSE
    BEGIN
        SET @norm = N'/' + @card_token + N'/' + @record_token;
        SET @is_form = 1;
        IF LOWER(@record_token) = N'new'
            SET @is_new = 1;
    END

    DECLARE @card_id int = NULL;
    DECLARE @card_name nvarchar(128) = NULL;
    DECLARE @tablename nvarchar(256) = NULL;
    DECLARE @basetable nvarchar(256) = NULL;
    DECLARE @id_column nvarchar(128) = NULL;
    DECLARE @list_cache nvarchar(max) = NULL;
    DECLARE @select_cache nvarchar(max) = NULL;
    DECLARE @declare_cache nvarchar(max) = NULL;
    DECLARE @sorting nvarchar(512) = NULL;
    DECLARE @record_limit int = NULL;
    DECLARE @auto_refresh int = NULL;
    DECLARE @crud_read nvarchar(max) = NULL;
    DECLARE @crud_delete nvarchar(max) = NULL;
    DECLARE @card_ide_role nvarchar(128) = NULL;
    DECLARE @is_system bit = 0;
    DECLARE @system_allowed bit = 1;
    DECLARE @parent_card_id int = NULL;
    DECLARE @rel_unbound bit = 0;
    DECLARE @rel_ref nvarchar(128) = NULL;
    DECLARE @rel_reducer nvarchar(max) = NULL;

    -- Look up the relation before the card. An unknown relation must not be
    -- overwritten by Unknown card.
    IF @in_child = 1
    BEGIN
        SELECT TOP (1)
            @parent_card_id = p.id,
            @rel_unbound = ISNULL(rel.unbound, 0),
            @rel_ref = NULLIF(LTRIM(RTRIM(rel.ref)), N''),
            @rel_reducer = NULLIF(LTRIM(RTRIM(rel.reducer)), N'')
        FROM dbo.api_card_children AS rel
        JOIN dbo.api_card AS p ON p.id = rel.parent
        JOIN dbo.api_card AS ch ON ch.id = rel.child
        WHERE p.name = @parent_card_name
          AND ch.name = @card_token
        ORDER BY rel.unbound, rel.action_order, rel.id;

        IF @parent_card_id IS NULL AND @error IS NULL
            SET @error = CONCAT(N'Unknown relation: ', @parent_card_name, N' / ', @card_token);
    END

    IF @norm <> N'/' AND @error IS NULL
    BEGIN
        SELECT
            @card_id = c.id,
            @card_name = c.name,
            @tablename = c.tablename,
            @basetable = c.basetable,
            @id_column = c.id_column,
            @list_cache = c.list_select_cache,
            @select_cache = c.select_cache,
            @declare_cache = c.declare_cache,
            @sorting = NULLIF(LTRIM(RTRIM(c.sorting_order)), N''),
            @record_limit = c.record_limit,
            @auto_refresh = c.auto_refresh_seconds,
            @crud_read = c.crud_read,
            @crud_delete = c.crud_delete,
            @card_ide_role = NULLIF(LTRIM(RTRIM(c.ide_role)), N''),
            @is_system = ISNULL(c.is_system, 0)
        FROM dbo.api_card AS c
        WHERE c.name = @card_token;

        IF @card_id IS NULL
            SET @error = CONCAT(N'Unknown card: ', @card_token);
    END

    -- is_system 1 is a system card. ide_role is the comma-separated roles
    -- that may see it. A blank ide_role does not restrict the card.
    -- is_system 0 does not consult ide_role, so a business card stays open.
    -- The role name comes from the row. The UI repeats this check on the
    -- token claim role.
    IF @card_id IS NOT NULL AND @is_system = 1 AND @card_ide_role IS NOT NULL
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM STRING_SPLIT(@card_ide_role, N',') AS need
            JOIN @role_hold AS held
              ON held.name = LTRIM(RTRIM(need.value))
            WHERE LTRIM(RTRIM(need.value)) <> N''
        )
        BEGIN
            SET @system_allowed = 0;
            IF @error IS NULL
                SET @error = CONCAT(N'Code editing requires the role ', @card_ide_role, N'.');
        END
    END

    DECLARE @context_id nvarchar(max) = COALESCE(NULLIF(@record_token, N''), NULLIF(@id, N''));

    DECLARE @was_open bit = 0;
    DECLARE @state_action int = NULL;
    DECLARE @state_path nvarchar(400) = NULL;
    SELECT
        @was_open = st.is_open,
        @state_action = st.action_id,
        @state_path = st.path
    FROM dbo.api_modal_state AS st
    WHERE st.session_id = @sid;

    DELETE FROM dbo.api_modal_render WHERE session_id = @sid;
    DELETE FROM dbo.api_toast WHERE session_id = @sid;
    DELETE FROM dbo.api_modal_post WHERE session_id = @sid;

    IF @posted_json IS NOT NULL AND ISJSON(@posted_json) = 1
    BEGIN
        INSERT INTO dbo.api_modal_post (session_id, name, value)
        SELECT @sid, j.[key], j.value
        FROM OPENJSON(@posted_json) AS j;
    END
    ELSE IF @posted_json IS NOT NULL
        AND LTRIM(RTRIM(@posted_json)) <> N''
        AND ISNULL(ISJSON(@posted_json), 0) = 0
        SET @error = N'posted_json is not valid JSON.';

    IF ISNULL(@close, 0) = 1
       OR (@was_open = 1 AND @state_path IS NOT NULL AND @state_path <> @norm)
    BEGIN
        UPDATE dbo.api_modal_state
        SET is_open = 0,
            clear_requested = 0,
            action_id = NULL,
            css_class = NULL,
            path = NULL
        WHERE session_id = @sid;
        IF @was_open = 1
            SET @cleared = 1;
        SET @was_open = 0;
    END

    -- A save or delete is the form post. It must not re-enter or keep an open modal.
    IF ISNULL(@save, 0) = 1 OR ISNULL(@delete, 0) = 1
    BEGIN
        IF @was_open = 1
            SET @cleared = 1;
        UPDATE dbo.api_modal_state
        SET is_open = 0,
            clear_requested = 0,
            action_id = NULL,
            css_class = NULL,
            path = NULL
        WHERE session_id = @sid;
        SET @was_open = 0;
    END

    DECLARE @explicit bit = CASE
        WHEN ISNULL(@save, 0) = 0
         AND ISNULL(@delete, 0) = 0
         AND @action IS NOT NULL
         AND LTRIM(RTRIM(@action)) <> N'' THEN 1
        ELSE 0
    END;

    DECLARE @run_id int = NULL;
    DECLARE @action_name nvarchar(128) = NULL;
    DECLARE @action_kind nvarchar(64) = NULL;
    DECLARE @action_sql nvarchar(max) = NULL;
    DECLARE @pre nvarchar(max) = NULL;

    IF @explicit = 1
    BEGIN
        UPDATE dbo.api_modal_state
        SET is_open = 0,
            action_id = NULL,
            css_class = NULL,
            path = NULL
        WHERE session_id = @sid;

        SELECT TOP (1)
            @run_id = a.id,
            @action_name = a.name,
            @action_kind = a.action,
            @action_sql = COALESCE(NULLIF(LTRIM(RTRIM(a.sql)), N''), NULLIF(LTRIM(RTRIM(a.unparsed_sql)), N'')),
            @pre = a.pre_declare
        FROM dbo.api_card_actions AS a
        WHERE a.name = @action
          AND (a.card_id = @card_id OR a.card_id IS NULL)
        ORDER BY CASE WHEN a.card_id = @card_id THEN 0 ELSE 1 END, a.id;

        IF @run_id IS NULL AND @error IS NULL
            SET @error = CONCAT(N'Unknown action: ', @action);
    END
    ELSE IF @was_open = 1 AND @state_action IS NOT NULL
    BEGIN
        SELECT
            @run_id = a.id,
            @action_name = a.name,
            @action_kind = a.action,
            @action_sql = COALESCE(NULLIF(LTRIM(RTRIM(a.sql)), N''), NULLIF(LTRIM(RTRIM(a.unparsed_sql)), N'')),
            @pre = a.pre_declare
        FROM dbo.api_card_actions AS a
        WHERE a.id = @state_action;

        IF @run_id IS NULL AND @error IS NULL
            SET @error = N'The modal action is no longer available.';
    END

    -- A pooled connection keeps the previous request. Named @value = NULL
    -- removes a key. A positional NULL is rejected.
    EXEC sp_set_session_context @key = N'id', @value = NULL;
    EXEC sp_set_session_context @key = N'ids', @value = NULL;
    EXEC sp_set_session_context @key = N'card_name', @value = NULL;
    EXEC sp_set_session_context @key = N'card_id', @value = NULL;
    EXEC sp_set_session_context @key = N'action_id', @value = NULL;
    EXEC sp_set_session_context @key = N'tablename', @value = NULL;
    EXEC sp_set_session_context @key = N'basetable', @value = NULL;
    EXEC sp_set_session_context @key = N'sub', @value = NULL;
    EXEC sp_set_session_context @key = N'parent_id', @value = NULL;
    EXEC sp_set_session_context @key = N'parent_card_name', @value = NULL;
    EXEC sp_set_session_context @key = N'parent_card_id', @value = NULL;

    -- sp_set_session_context rejects a positional NULL and nvarchar(max).
    -- Skip empty keys and cast long text to nvarchar(4000).
    IF @sid IS NOT NULL
        EXEC sp_set_session_context N'session_id', @sid;
    IF @main_db IS NOT NULL
        EXEC sp_set_session_context N'main_db', @main_db;
    IF @user_name IS NOT NULL
    BEGIN
        EXEC sp_set_session_context N'user', @user_name;
        EXEC sp_set_session_context N'user_name', @user_name;
    END
    IF @user_id IS NOT NULL
        EXEC sp_set_session_context N'user_id', @user_id;
    IF @context_id IS NOT NULL
    BEGIN
        DECLARE @id_ctx nvarchar(4000) = CONVERT(nvarchar(4000), @context_id);
        EXEC sp_set_session_context N'id', @id_ctx;
    END
    IF @ids IS NOT NULL
    BEGIN
        DECLARE @ids_ctx nvarchar(4000) = CONVERT(nvarchar(4000), @ids);
        EXEC sp_set_session_context N'ids', @ids_ctx;
    END
    IF @card_name IS NOT NULL
        EXEC sp_set_session_context N'card_name', @card_name;
    IF @card_id IS NOT NULL
        EXEC sp_set_session_context N'card_id', @card_id;
    IF @norm IS NOT NULL
        EXEC sp_set_session_context N'path', @norm;
    EXEC sp_set_session_context N'is_form', @is_form;
    IF @run_id IS NOT NULL
        EXEC sp_set_session_context N'action_id', @run_id;
    IF @tablename IS NOT NULL
        EXEC sp_set_session_context N'tablename', @tablename;
    IF @basetable IS NOT NULL
        EXEC sp_set_session_context N'basetable', @basetable;
    IF @caller_sub IS NOT NULL AND LTRIM(RTRIM(@caller_sub)) <> N''
    BEGIN
        DECLARE @sub_ctx nvarchar(4000) = CONVERT(nvarchar(4000), LTRIM(RTRIM(@caller_sub)));
        EXEC sp_set_session_context N'sub', @sub_ctx;
    END
    IF @in_child = 1
    BEGIN
        IF @parent_record IS NOT NULL AND @parent_record <> N'' AND @parent_record <> N'-'
        BEGIN
            DECLARE @parent_ctx nvarchar(4000) = CONVERT(nvarchar(4000), @parent_record);
            EXEC sp_set_session_context N'parent_id', @parent_ctx;
        END
        IF @parent_card_name IS NOT NULL
            EXEC sp_set_session_context N'parent_card_name', @parent_card_name;
        IF @parent_card_id IS NOT NULL
            EXEC sp_set_session_context N'parent_card_id', @parent_card_id;
    END

    IF @run_id IS NOT NULL
       AND @action_kind = N'stored_procedure'
       AND @error IS NULL
    BEGIN
        IF @action_sql IS NULL
        BEGIN
            IF @action_name LIKE N'%[^A-Za-z0-9_]%' OR @action_name LIKE N'[0-9]%'
                SET @error = N'Action name cannot be executed.';
            ELSE
                SET @action_sql = N'EXEC dbo.' + QUOTENAME(@action_name);
        END
    END

    IF @run_id IS NOT NULL
       AND @action_kind = N'stored_procedure'
       AND @action_sql IS NOT NULL
       AND @error IS NULL
    BEGIN
        DECLARE @pre_sql nvarchar(max) = N'';
        IF @pre IS NOT NULL AND LTRIM(RTRIM(@pre)) <> N''
        BEGIN
            DECLARE @flat nvarchar(max) = REPLACE(REPLACE(@pre, CHAR(13), N' '), CHAR(10), N' ');
            IF EXISTS (
                SELECT 1
                FROM dbo.fn_split_declare(@flat) AS s
                CROSS APPLY (
                    SELECT
                        LEFT(s.item, CHARINDEX(N' ', s.item + N' ') - 1) AS varname,
                        CASE
                            WHEN CHARINDEX(N' ', LTRIM(RTRIM(s.item))) = 0 THEN N'nvarchar(max)'
                            ELSE LTRIM(RTRIM(SUBSTRING(s.item, CHARINDEX(N' ', s.item) + 1, 200)))
                        END AS typ
                ) AS v
                WHERE v.varname NOT LIKE N'@[A-Za-z_]%'
                   OR v.varname LIKE N'%[^@A-Za-z0-9_]%'
                   OR v.typ LIKE N'%;%'
                   OR v.typ LIKE N'%--%'
                   OR v.typ LIKE N'%/*%'
            )
                SET @error = N'pre_declare contains an unsupported declaration.';
            ELSE
            BEGIN
                SELECT @pre_sql = STRING_AGG(CAST(part.line AS nvarchar(max)), CHAR(10))
                    WITHIN GROUP (ORDER BY part.ord)
                FROM (
                    SELECT
                        s.ord,
                        N'DECLARE ' + v.varname + N' ' + v.typ + N';' + CHAR(10)
                        + N'EXEC dbo.sp_api_modal_get_value N''' + v.varname + N''', ' + v.varname + N' OUTPUT;' AS line
                    FROM dbo.fn_split_declare(@flat) AS s
                    CROSS APPLY (
                        SELECT
                            LEFT(s.item, CHARINDEX(N' ', s.item + N' ') - 1) AS varname,
                            CASE
                                WHEN CHARINDEX(N' ', LTRIM(RTRIM(s.item))) = 0 THEN N'nvarchar(max)'
                                ELSE LTRIM(RTRIM(SUBSTRING(s.item, CHARINDEX(N' ', s.item) + 1, 200)))
                            END AS typ
                    ) AS v
                    WHERE v.varname NOT IN (
                        N'@id', N'@ids', N'@card_name', N'@card_id', N'@user', N'@user_name', N'@user_id',
                        N'@main_db', N'@path', N'@previous_path', N'@parent_id', N'@parent_card_name',
                        N'@parent_card_id', N'@is_form', N'@tablename', N'@basetable', N'@identity_column'
                    )
                ) AS part;
            END
        END

        IF @error IS NULL
        BEGIN
            DECLARE @batch nvarchar(max) = N'SET NOCOUNT ON;' + CHAR(10)
                + N'DECLARE @id nvarchar(max) = @p_id;' + CHAR(10)
                + N'DECLARE @ids nvarchar(max) = @p_ids;' + CHAR(10)
                + N'DECLARE @card_name nvarchar(128) = @p_card_name;' + CHAR(10)
                + N'DECLARE @card_id int = @p_card_id;' + CHAR(10)
                + N'DECLARE @user nvarchar(256) = @p_user;' + CHAR(10)
                + N'DECLARE @user_name nvarchar(256) = @p_user;' + CHAR(10)
                + N'DECLARE @user_id int = @p_user_id;' + CHAR(10)
                + N'DECLARE @main_db nvarchar(128) = @p_main_db;' + CHAR(10)
                + N'DECLARE @path nvarchar(400) = @p_path;' + CHAR(10)
                + N'DECLARE @previous_path nvarchar(400) = NULL;' + CHAR(10)
                + N'DECLARE @parent_id int = TRY_CONVERT(int, @p_parent_id);' + CHAR(10)
                + N'DECLARE @parent_card_name nvarchar(128) = @p_parent_card_name;' + CHAR(10)
                + N'DECLARE @parent_card_id int = @p_parent_card_id;' + CHAR(10)
                + N'DECLARE @is_form bit = @p_is_form;' + CHAR(10)
                + N'DECLARE @tablename nvarchar(256) = @p_tablename;' + CHAR(10)
                + N'DECLARE @basetable nvarchar(256) = @p_basetable;' + CHAR(10)
                + N'DECLARE @identity_column nvarchar(128) = @p_id_column;' + CHAR(10)
                + ISNULL(@pre_sql, N'') + CHAR(10)
                + @action_sql;

            DECLARE @pass_parent_id nvarchar(128) = NULL;
            DECLARE @pass_parent_name nvarchar(128) = NULL;
            DECLARE @pass_parent_card int = NULL;
            IF @in_child = 1
            BEGIN
                IF @parent_record IS NOT NULL AND @parent_record <> N'' AND @parent_record <> N'-'
                    SET @pass_parent_id = @parent_record;
                SET @pass_parent_name = @parent_card_name;
                SET @pass_parent_card = @parent_card_id;
            END

            BEGIN TRY
                EXEC sp_executesql
                    @batch,
                    N'@p_id nvarchar(max), @p_ids nvarchar(max), @p_card_name nvarchar(128), @p_card_id int, @p_user nvarchar(256), @p_user_id int, @p_main_db nvarchar(128), @p_path nvarchar(400), @p_is_form bit, @p_tablename nvarchar(256), @p_basetable nvarchar(256), @p_id_column nvarchar(128), @p_parent_id nvarchar(128), @p_parent_card_name nvarchar(128), @p_parent_card_id int',
                    @p_id = @context_id,
                    @p_ids = @ids,
                    @p_card_name = @card_name,
                    @p_card_id = @card_id,
                    @p_user = @user_name,
                    @p_user_id = @user_id,
                    @p_main_db = @main_db,
                    @p_path = @norm,
                    @p_is_form = @is_form,
                    @p_tablename = @tablename,
                    @p_basetable = @basetable,
                    @p_id_column = @id_column,
                    @p_parent_id = @pass_parent_id,
                    @p_parent_card_name = @pass_parent_name,
                    @p_parent_card_id = @pass_parent_card;
            END TRY
            BEGIN CATCH
                SET @error = ERROR_MESSAGE();
            END CATCH
        END
    END

    DECLARE @allowed bit = 1;
    IF @card_id IS NOT NULL
       AND @crud_read IS NOT NULL
       AND LTRIM(RTRIM(@crud_read)) <> N''
       AND @error IS NULL
    BEGIN
        IF @crud_read LIKE N'%;%' OR @crud_read LIKE N'%--%'
            SET @error = N'crud_read is not a single expression.';
        ELSE
        BEGIN
            BEGIN TRY
                DECLARE @gate nvarchar(max) = N'SELECT @allowed = CASE WHEN (' + @crud_read + N') THEN 1 ELSE 0 END;';
                EXEC sp_executesql
                    @gate,
                    N'@allowed bit OUTPUT',
                    @allowed = @allowed OUTPUT;
            END TRY
            BEGIN CATCH
                SET @allowed = 0;
                SET @error = CONCAT(N'crud_read failed: ', ERROR_MESSAGE());
            END CATCH
            IF @allowed = 0 AND @error IS NULL
                SET @error = N'Read is not allowed for this card.';
        END
    END

    DECLARE @data nvarchar(max) = N'[]';
    DECLARE @def nvarchar(max) = N'[]';
    DECLARE @actions nvarchar(max) = N'[]';
    DECLARE @settings nvarchar(max) = NULL;
    DECLARE @breadcrumbs nvarchar(max) = N'[]';
    DECLARE @header nvarchar(max) = N'[]';
    DECLARE @views nvarchar(max) = NULL;
    DECLARE @relations nvarchar(max) = NULL;
    DECLARE @held_error nvarchar(400) = NULL;

    IF ISNULL(@delete, 0) = 1 AND @error IS NULL AND @allowed = 1
    BEGIN
        IF @card_id IS NULL OR ISNULL(@is_form, 0) = 0
            SET @error = N'Delete is only available on a form.';
        ELSE IF ISNULL(@is_new, 0) = 1
            SET @error = N'Choose a record to delete.';
        ELSE
        BEGIN
            DECLARE @deleted_id nvarchar(128);
            DECLARE @delete_error nvarchar(400);
            DECLARE @delete_key nvarchar(128) = CONVERT(nvarchar(128), @context_id);
            DECLARE @do_delete bit = 1;
            DECLARE @delete_is_new bit = 0;
            EXEC dbo.sp_api_card_save
                @card_id = @card_id,
                @id = @delete_key,
                @is_new = @delete_is_new,
                @values_json = @values_json,
                @new_id = @deleted_id OUTPUT,
                @error = @delete_error OUTPUT,
                @delete = @do_delete;
            SET @error = @delete_error;
            IF @error IS NULL
            BEGIN
                EXEC dbo.sp_api_toast @text = N'Deleted', @class = N'text-success';
                SET @is_form = 0;
                SET @is_new = 0;
                SET @record_token = NULL;
                SET @context_id = NULL;
                IF @in_child = 1
                    SET @norm = N'/' + @parent_card_name + N'/' + ISNULL(@parent_record, N'') + N'/' + @card_name;
                ELSE
                    SET @norm = N'/' + @card_name;
                EXEC sp_set_session_context @key = N'id', @value = NULL;
                EXEC sp_set_session_context @key = N'path', @value = @norm;
                EXEC sp_set_session_context @key = N'is_form', @value = @is_form;
            END
        END
        -- The form load below skips a request that already has an error.
        -- Hold a failed delete so the record is read, then put the message back.
        IF @error IS NOT NULL AND @card_id IS NOT NULL AND ISNULL(@is_form, 0) = 1
        BEGIN
            SET @held_error = @error;
            SET @error = NULL;
        END
    END
    ELSE IF ISNULL(@save, 0) = 1 AND @error IS NULL AND @allowed = 1
    BEGIN
        IF @card_id IS NULL OR ISNULL(@is_form, 0) = 0
            SET @error = N'Save is only available on a form.';
        ELSE
        BEGIN
            DECLARE @saved_id nvarchar(128);
            DECLARE @save_error nvarchar(400);
            DECLARE @save_key nvarchar(128) = CONVERT(nvarchar(128), @context_id);
            EXEC dbo.sp_api_card_save
                @card_id = @card_id,
                @id = @save_key,
                @is_new = @is_new,
                @values_json = @values_json,
                @new_id = @saved_id OUTPUT,
                @error = @save_error OUTPUT;
            SET @error = @save_error;
            IF @error IS NULL
            BEGIN
                EXEC dbo.sp_api_toast @text = N'Saved', @class = N'text-success';
                IF @is_new = 1
                BEGIN
                    SET @is_new = 0;
                    SET @record_token = @saved_id;
                    SET @context_id = @saved_id;
                    IF @in_child = 1
                        SET @norm = N'/' + @parent_card_name + N'/' + @parent_record + N'/' + @card_name + N'/' + @saved_id;
                    ELSE
                        SET @norm = N'/' + @card_name + N'/' + @saved_id;
                    DECLARE @saved_ctx nvarchar(4000) = CONVERT(nvarchar(4000), @saved_id);
                    EXEC sp_set_session_context N'id', @saved_ctx;
                    EXEC sp_set_session_context N'path', @norm;
                END
            END
            ELSE IF @values_json IS NOT NULL
                AND ISJSON(@values_json) = 1
                AND LEFT(LTRIM(@values_json), 1) = N'{'
                SET @data = N'[' + @values_json + N']';
        END
    END

    -- A failed child path is not the home menu. Home is only a bare /.
    IF @card_id IS NULL AND @in_child = 0
    BEGIN
        SELECT @header = (
            SELECT
                c.id,
                c.name,
                c.name AS disp,
                c.menu_keycode AS keycode,
                CAST(ISNULL(c.is_system, 0) AS bit) AS is_system,
                NULLIF(LTRIM(RTRIM(c.ide_role)), N'') AS ide_role
            FROM dbo.api_card AS c
            WHERE c.in_main_menu = 1
            ORDER BY c.name
            FOR JSON PATH
        );
        SET @header = COALESCE(@header, N'[]');
        SET @data = @header;
    END
    ELSE IF @error IS NULL AND @allowed = 1
    BEGIN
        IF @is_form = 1 AND @is_new = 1
        BEGIN
            SET @data = N'[{}]';
            IF @in_child = 1 AND ISNULL(@rel_unbound, 0) = 0
            BEGIN
                IF @rel_ref IS NULL
                   OR @rel_ref LIKE N'%[^A-Za-z0-9_]%'
                   OR @rel_ref LIKE N'[0-9]%'
                    SET @error = N'This relation has no link column.';
                ELSE IF @parent_record IS NULL OR @parent_record = N'' OR @parent_record = N'-'
                    SET @error = N'Choose a record to open this related card.';
                ELSE
                BEGIN
                    -- JSON_MODIFY requires a string literal for the path, so the
                    -- checked column name is pasted into its own batch.
                    DECLARE @link_int int = TRY_CONVERT(int, @parent_record);
                    DECLARE @prefill nvarchar(max) = N'SET @data = JSON_MODIFY(N''[{}]'', N''$[0].' + @rel_ref + N''', @link);';
                    IF @link_int IS NOT NULL AND CONVERT(nvarchar(30), @link_int) = @parent_record
                        EXEC sp_executesql
                            @prefill,
                            N'@link int, @data nvarchar(max) OUTPUT',
                            @link = @link_int,
                            @data = @data OUTPUT;
                    ELSE
                        EXEC sp_executesql
                            @prefill,
                            N'@link nvarchar(128), @data nvarchar(max) OUTPUT',
                            @link = @parent_record,
                            @data = @data OUTPUT;
                    SET @data = COALESCE(@data, N'[{}]');
                END
            END
        END
        ELSE IF @is_form = 1
        BEGIN
            IF @select_cache IS NULL OR @declare_cache IS NULL
                SET @error = N'cache not built';
            ELSE
            BEGIN
                DECLARE @proj nvarchar(max);
                SELECT @proj = STRING_AGG(
                    CAST(QUOTENAME(x.name) + N' = @' + x.name AS nvarchar(max)),
                    N', '
                ) WITHIN GROUP (ORDER BY x.ord, x.name)
                FROM (
                    SELECT @id_column AS name, 0 AS ord
                    UNION ALL
                    SELECT f.name, ISNULL(f.detail_order, 0)
                    FROM dbo.api_card_fields AS f
                    WHERE f.card_id = @card_id
                      AND ISNULL(f.detail_order, 0) > 0
                      AND f.name <> @id_column
                ) AS x;

                DECLARE @form_batch nvarchar(max) = @declare_cache + CHAR(10)
                    + @select_cache + CHAR(10)
                    + N'IF @@ROWCOUNT = 0 SET @json = N''[]''; ELSE SELECT @json = (SELECT '
                    + @proj + N' FOR JSON PATH);';
                BEGIN TRY
                    EXEC sp_executesql
                        @form_batch,
                        N'@id_text nvarchar(max), @json nvarchar(max) OUTPUT',
                        @id_text = @context_id,
                        @json = @data OUTPUT;
                    SET @data = COALESCE(@data, N'[]');
                END TRY
                BEGIN CATCH
                    SET @error = ERROR_MESSAGE();
                    SET @data = N'[]';
                END CATCH

                IF @error IS NULL
                   AND @in_child = 1
                   AND ISNULL(@rel_unbound, 0) = 0
                   AND ISNULL(@data, N'[]') <> N'[]'
                BEGIN
                    IF @rel_ref IS NULL
                       OR @rel_ref LIKE N'%[^A-Za-z0-9_]%'
                       OR @rel_ref LIKE N'[0-9]%'
                    BEGIN
                        SET @error = N'This relation has no link column.';
                        SET @data = N'[]';
                    END
                    ELSE IF @parent_record IS NULL OR @parent_record = N'' OR @parent_record = N'-'
                    BEGIN
                        SET @error = N'Choose a record to open this related card.';
                        SET @data = N'[]';
                    END
                    ELSE
                    BEGIN
                        -- OPENJSON keys are a binary collation. Compare as text.
                        -- A null link is omitted by FOR JSON, so a missing key fails closed.
                        DECLARE @member nvarchar(128) = NULL;
                        SELECT @member = CONVERT(nvarchar(128), j.[value])
                        FROM OPENJSON(@data, N'$[0]') AS j
                        WHERE j.[key] COLLATE DATABASE_DEFAULT = @rel_ref;

                        IF @member IS NULL OR @member <> CONVERT(nvarchar(128), @parent_record)
                        BEGIN
                            SET @error = N'This record is not part of the related card.';
                            SET @data = N'[]';
                        END
                    END
                END
            END
        END
        ELSE
        BEGIN
            IF @list_cache IS NULL
                SET @error = N'cache not built';
            ELSE IF @sorting LIKE N'%;%' OR @sorting LIKE N'%--%'
                SET @error = N'sorting_order is not a single expression.';
            ELSE
            BEGIN
                -- The filter uses list output names on cached. The cache alias t
                -- is inside the subquery, so a reducer writes status, not t.status.
                DECLARE @child_where nvarchar(max) = N'';
                IF @in_child = 1
                BEGIN
                    IF ISNULL(@rel_unbound, 0) = 1
                    BEGIN
                        IF @rel_reducer IS NOT NULL
                        BEGIN
                            IF @rel_reducer LIKE N'%;%' OR @rel_reducer LIKE N'%--%' OR @rel_reducer LIKE N'%/*%'
                                SET @error = N'The relation filter is not a single expression.';
                            ELSE
                                SET @child_where = N' WHERE (' + @rel_reducer + N') ';
                        END
                    END
                    ELSE IF @rel_ref IS NULL
                        OR @rel_ref LIKE N'%[^A-Za-z0-9_]%'
                        OR @rel_ref LIKE N'[0-9]%'
                        SET @error = N'This relation has no link column.';
                    ELSE IF @parent_record IS NULL OR @parent_record = N'' OR @parent_record = N'-'
                        SET @error = N'Choose a record to open this related card.';
                    ELSE
                        SET @child_where = N' WHERE CONVERT(nvarchar(128), cached.' + QUOTENAME(@rel_ref) + N') = @parent_id ';
                END

                IF @error IS NULL
                BEGIN
                    DECLARE @list_batch nvarchar(max) = N'SELECT @json = (SELECT '
                        + CASE
                            WHEN @record_limit IS NOT NULL AND @record_limit > 0
                            THEN N'TOP (' + CONVERT(nvarchar(20), @record_limit) + N') '
                            ELSE N''
                          END
                        + N'* FROM (' + CHAR(10) + @list_cache + CHAR(10) + N') AS cached '
                        + @child_where
                        + CASE WHEN @sorting IS NOT NULL THEN N'ORDER BY ' + @sorting + N' ' ELSE N'' END
                        + N'FOR JSON PATH);';
                    BEGIN TRY
                        EXEC sp_executesql
                            @list_batch,
                            N'@json nvarchar(max) OUTPUT, @parent_id nvarchar(128)',
                            @json = @data OUTPUT,
                            @parent_id = @parent_record;
                        SET @data = COALESCE(@data, N'[]');
                    END TRY
                    BEGIN CATCH
                        SET @error = ERROR_MESSAGE();
                        SET @data = N'[]';
                    END CATCH
                END
            END
        END
    END

    IF @card_id IS NOT NULL AND @system_allowed = 1
    BEGIN
        IF @basetable IS NOT NULL
           AND @main_db IS NOT NULL
           AND @main_db NOT LIKE N'%[^A-Za-z0-9_]%'
           AND @main_db NOT LIKE N'[0-9]%'
           AND @basetable NOT LIKE N'%[^A-Za-z0-9_]%'
           AND @basetable NOT LIKE N'[0-9]%'
        BEGIN
            DECLARE @type_sql nvarchar(max) = N'
                INSERT INTO #coltype (name, typ)
                SELECT c.name, ty.name
                FROM ' + QUOTENAME(@main_db) + N'.sys.columns AS c
                INNER JOIN ' + QUOTENAME(@main_db) + N'.sys.types AS ty
                    ON ty.user_type_id = c.user_type_id
                INNER JOIN ' + QUOTENAME(@main_db) + N'.sys.tables AS t
                    ON t.object_id = c.object_id
                INNER JOIN ' + QUOTENAME(@main_db) + N'.sys.schemas AS s
                    ON s.schema_id = t.schema_id
                WHERE s.name = N''dbo''
                  AND t.name = @table
                  AND c.name NOT LIKE N''%[^A-Za-z0-9_]%'';';
            BEGIN TRY
                EXEC sp_executesql @type_sql, N'@table nvarchar(128)', @table = @basetable;
            END TRY
            BEGIN CATCH
                -- The screen still renders when the base table cannot be read.
            END CATCH
        END

        SELECT @def = (
            SELECT
                f.name AS name,
                COALESCE(f.display_name, f.name) AS disp,
                COALESCE(NULLIF(LTRIM(RTRIM(f.data_type)), N''), ct.typ, N'') AS typ,
                N'' AS att,
                CAST(CASE WHEN f.name = @id_column THEN 1 ELSE 0 END AS bit) AS is_id,
                CAST(CASE
                    WHEN f.name <> @id_column
                     AND ISNULL(f.detail_order, 0) > 0
                     AND NULLIF(LTRIM(RTRIM(f.sql)), N'') IS NULL THEN 1
                    ELSE 0
                END AS bit) AS is_upd,
                CAST(CASE
                    WHEN @is_form = 1 AND ISNULL(f.detail_order, 0) = 0 THEN 1
                    WHEN @is_form = 0 AND ISNULL(f.list_order, 0) = 0 THEN 1
                    ELSE 0
                END AS bit) AS is_hid,
                f.list_class AS cls,
                f.id AS id,
                f.id AS fid,
                f.list_order,
                f.detail_order
            FROM dbo.api_card_fields AS f
            LEFT JOIN #coltype AS ct ON ct.name = f.name
            WHERE f.card_id = @card_id
            ORDER BY
                CASE WHEN @is_form = 1 THEN ISNULL(f.detail_order, 0) ELSE ISNULL(f.list_order, 0) END,
                f.id
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SET @def = COALESCE(@def, N'[]');

        SELECT @breadcrumbs = (
            SELECT b.disp, b.card_name, b.pathname, N'' AS search
            FROM (
                SELECT
                    @parent_card_name AS disp,
                    @parent_card_name AS card_name,
                    N'/' + @parent_card_name AS pathname,
                    0 AS ord
                WHERE @in_child = 1
                UNION ALL
                SELECT
                    @parent_record,
                    @parent_card_name,
                    N'/' + @parent_card_name + N'/' + @parent_record,
                    1
                WHERE @in_child = 1
                  AND @parent_record IS NOT NULL
                  AND @parent_record <> N''
                  AND @parent_record <> N'-'
                UNION ALL
                SELECT
                    @card_name,
                    @card_name,
                    CASE
                        WHEN @in_child = 1
                        THEN N'/' + @parent_card_name + N'/' + ISNULL(@parent_record, N'') + N'/' + @card_name
                        ELSE N'/' + @card_name
                    END,
                    2
                UNION ALL
                SELECT
                    CASE WHEN @is_new = 1 THEN N'New' ELSE CONVERT(nvarchar(128), @context_id) END,
                    @card_name,
                    @norm,
                    3
                WHERE @is_form = 1
            ) AS b
            ORDER BY b.ord
            FOR JSON PATH
        );

        SELECT @actions = (
            SELECT
                a.name AS name,
                COALESCE(a.display_name, a.name) AS disp,
                a.action AS action,
                JSON_QUERY(CASE WHEN ISJSON(a.params) = 1 THEN a.params END) AS params,
                a.keycode AS keycode,
                CAST(NULL AS nvarchar(64)) AS groupname,
                a.type AS type
            FROM dbo.api_card_actions AS a
            WHERE a.card_id = @card_id
               OR a.card_id IS NULL
            ORDER BY a.action_order, a.id
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SET @actions = COALESCE(@actions, N'[]');
        SELECT @relations = (
            SELECT
                ch.name AS name,
                COALESCE(rel.display_name, ch.name) AS disp,
                rel.keycode AS keycode,
                CAST(ISNULL(rel.unbound, 0) AS bit) AS unbound,
                rel.ref AS ref
            FROM dbo.api_card_children AS rel
            JOIN dbo.api_card AS ch ON ch.id = rel.child
            WHERE rel.parent = @card_id
              AND ISNULL(rel.is_hidden, 0) = 0
            ORDER BY rel.action_order, rel.id
            FOR JSON PATH, INCLUDE_NULL_VALUES
        );
        SET @relations = COALESCE(@relations, N'[]');
        SELECT @header = (
            SELECT
                a.id,
                a.name,
                COALESCE(a.display_name, a.name) AS disp,
                a.action AS action,
                a.keycode
            FROM dbo.api_card_actions AS a
            WHERE a.card_id = @card_id
               OR a.card_id IS NULL
            ORDER BY a.action_order, a.id
            FOR JSON PATH
        );
        SET @header = COALESCE(@header, N'[]');
    END

    IF @held_error IS NOT NULL
        SET @error = @held_error;

    DECLARE @can_delete nvarchar(1) = N'0';
    IF @card_id IS NOT NULL AND @system_allowed = 1
    BEGIN
        IF @crud_delete IS NULL OR LTRIM(RTRIM(@crud_delete)) = N''
            SET @can_delete = N'1';
        ELSE IF @crud_delete LIKE N'%;%' OR @crud_delete LIKE N'%--%' OR @crud_delete LIKE N'%/*%'
        BEGIN
            SET @can_delete = N'0';
            IF @error IS NULL
                SET @error = N'The save rule is not a single expression.';
        END
        ELSE
        BEGIN
            DECLARE @delete_ok bit = 0;
            BEGIN TRY
                DECLARE @can_sql nvarchar(max) = N'SELECT @allowed = CASE WHEN (' + @crud_delete + N') THEN 1 ELSE 0 END;';
                EXEC sp_executesql
                    @can_sql,
                    N'@allowed bit OUTPUT',
                    @allowed = @delete_ok OUTPUT;
            END TRY
            BEGIN CATCH
                SET @delete_ok = 0;
                IF @error IS NULL
                    SET @error = N'The save rule failed.';
            END CATCH
            IF @delete_ok = 1
                SET @can_delete = N'1';
        END
    END

    SELECT @settings = (
        SELECT v.k, v.v
        FROM (VALUES
            (N'cardname', @card_name),
            (N'user', @user_name),
            (N'main_db', @main_db),
            (N'id_column', @id_column),
            (N'record_limit', CONVERT(nvarchar(20), @record_limit)),
            (N'auto_refresh_seconds', CONVERT(nvarchar(20), @auto_refresh)),
            (N'is_form', CONVERT(nvarchar(1), @is_form)),
            (N'is_list', CASE WHEN @is_form = 1 THEN N'0' ELSE N'1' END),
            (N'can_delete', @can_delete),
            (N'is_system', CONVERT(nvarchar(1), ISNULL(@is_system, 0))),
            (N'ide_role', @card_ide_role)
        ) AS v(k, v)
        FOR JSON PATH, INCLUDE_NULL_VALUES
    );

    DECLARE @modal nvarchar(max) = NULL;
    DECLARE @modal_class nvarchar(128) = NULL;
    DECLARE @clear_requested bit = 0;
    DECLARE @controls nvarchar(max) = NULL;
    DECLARE @modal_action int = NULL;
    DECLARE @modal_edit nvarchar(128) = NULL;

    SELECT
        @modal_class = st.css_class,
        @clear_requested = st.clear_requested,
        @modal_action = st.action_id
    FROM dbo.api_modal_state AS st
    WHERE st.session_id = @sid;

    -- The edit path opens the action-code card. The UI decides whether to
    -- paint it by comparing the token claim role with this card's ide_role
    -- when is_system is 1. A blank ide_role leaves the button available.
    DECLARE @editor_card nvarchar(128) = N'ide_action';
    DECLARE @editor_role nvarchar(128) = NULL;
    DECLARE @editor_system bit = 0;
    IF @modal_action IS NOT NULL
    BEGIN
        SET @modal_edit = N'/' + @editor_card + N'/' + CONVERT(nvarchar(20), @modal_action);
        SELECT
            @editor_role = NULLIF(LTRIM(RTRIM(ide_role)), N''),
            @editor_system = ISNULL(is_system, 0)
        FROM dbo.api_card
        WHERE name = @editor_card;
    END

    SELECT @controls = STRING_AGG(CAST(r.payload AS nvarchar(max)), N',')
        WITHIN GROUP (ORDER BY r.seq)
    FROM dbo.api_modal_render AS r
    WHERE r.session_id = @sid;

    IF @controls IS NOT NULL
    BEGIN
        SET @modal = N'{"class":'
            + CASE
                WHEN @modal_class IS NULL THEN N'null'
                ELSE N'"' + STRING_ESCAPE(@modal_class, 'json') + N'"'
              END
            + N',"controls":[' + @controls + N']'
            + CASE
                WHEN @modal_edit IS NULL THEN N''
                ELSE N',"edit":"' + STRING_ESCAPE(@modal_edit, 'json') + N'"'
                    + N',"is_system":' + CASE WHEN @editor_system = 1 THEN N'1' ELSE N'0' END
                    + N',"ide_role":'
                    + CASE
                        WHEN @editor_role IS NULL THEN N'null'
                        ELSE N'"' + STRING_ESCAPE(@editor_role, 'json') + N'"'
                      END
              END
            + N'}';
    END

    IF @clear_requested = 1 AND @controls IS NULL
        SET @cleared = 1;

    UPDATE dbo.api_modal_state
    SET clear_requested = 0
    WHERE session_id = @sid;

    DECLARE @toasts nvarchar(max) = NULL;
    SELECT @toasts = (
        SELECT t.text AS text, t.css_class AS class
        FROM dbo.api_toast AS t
        WHERE t.session_id = @sid
        ORDER BY t.id
        FOR JSON PATH, INCLUDE_NULL_VALUES
    );
    SET @toasts = COALESCE(@toasts, N'[]');

    -- The shell paints breadcrumb + json.actions whenever actions is truthy.
    -- The Actions view paints header links and then that same bar again.
    -- Home keeps Actions and sends actions NULL so the bar is painted once.
    -- A card keeps the action buttons and does not include the Actions view.
    IF @card_id IS NULL
    BEGIN
        SET @views = N'[{"comp":"Actions","data":"header"}]';
        SET @actions = NULL;
    END
    ELSE
        SET @views = N'[{"comp":"'
            + CASE WHEN @is_form = 1 THEN N'Detailview' ELSE N'Listview' END
            + N'","data":"data"}]';

    DECLARE @payload nvarchar(max);
    SET @payload = (
        SELECT
            @session_token AS session,
            JSON_QUERY(@data) AS data,
            JSON_QUERY(@def) AS [def],
            JSON_QUERY(@actions) AS actions,
            JSON_QUERY(@relations) AS relations,
            JSON_QUERY(@header) AS header,
            JSON_QUERY(@settings) AS settings,
            JSON_QUERY(@breadcrumbs) AS breadcrumbs,
            JSON_QUERY(@views) AS views,
            JSON_QUERY(N'[]') AS statusbar,
            JSON_QUERY(N'[]') AS querystring,
            JSON_QUERY(@modal) AS modal,
            JSON_QUERY(@toasts) AS toasts,
            CAST(@cleared AS bit) AS cleared,
            @error AS error
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );

    SELECT payload = @payload;
END
GO
