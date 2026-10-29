USE demo_proj;
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_card_create_cache
    @card_id int,
    @toast   bit = 0,
    @main_db nvarchar(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @card_name nvarchar(128);
    DECLARE @tablename nvarchar(256);
    DECLARE @id_column nvarchar(128);
    DECLARE @reducer nvarchar(max);
    DECLARE @error nvarchar(2048);
    DECLARE @throw_number int;
    DECLARE @throw_state int = 1;

    SELECT
        @card_name = c.name,
        @tablename = c.tablename,
        @id_column = NULLIF(LTRIM(RTRIM(c.id_column)), N''),
        @reducer = NULLIF(LTRIM(RTRIM(c.reducer)), N'')
    FROM dbo.api_card AS c
    WHERE c.id = @card_id;

    IF @card_name IS NULL
    BEGIN
        SET @error = CONCAT(N'sp_api_card_create_cache: card ', @card_id, N' was not found.');
        SET @throw_number = 50020;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF @id_column IS NULL
    BEGIN
        SET @error = N'sp_api_card_create_cache NO ID!';
        UPDATE dbo.api_card SET error = @error WHERE id = @card_id;
        IF @toast = 1
        BEGIN
            DECLARE @no_id_toast nvarchar(max) = CONCAT(N'Cache error: ', @error);
            EXEC dbo.sp_api_toast @text = @no_id_toast;
        END
        SET @throw_number = 50021;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF @id_column LIKE N'%[^A-Za-z0-9_]%' OR @id_column LIKE N'[0-9]%'
    BEGIN
        SET @error = N'id_column must be a plain identifier.';
        UPDATE dbo.api_card SET error = @error WHERE id = @card_id;
        SET @throw_number = 50022;
        ;THROW @throw_number, @error, @throw_state;
    END

    BEGIN TRY
        IF @main_db IS NULL OR LTRIM(RTRIM(@main_db)) = N''
            SET @main_db = dbo.main_db();

        IF @tablename IS NULL OR LTRIM(RTRIM(@tablename)) = N''
        BEGIN
            SET @error = N'tablename is not set.';
            SET @throw_number = 50023;
            ;THROW @throw_number, @error, @throw_state;
        END

        IF @reducer LIKE N'%;%'
        BEGIN
            SET @error = N'reducer must be a single predicate without a semicolon.';
            SET @throw_number = 50024;
            ;THROW @throw_number, @error, @throw_state;
        END

        DECLARE @db nvarchar(128) = COALESCE(PARSENAME(@tablename, 3), @main_db);
        DECLARE @schema nvarchar(128) = COALESCE(PARSENAME(@tablename, 2), N'dbo');
        DECLARE @object nvarchar(128) = PARSENAME(@tablename, 1);

        IF @object IS NULL OR @db IS NULL OR @schema IS NULL
        BEGIN
            SET @error = N'tablename could not be parsed. Use name, schema.name, or db.schema.name.';
            SET @throw_number = 50025;
            ;THROW @throw_number, @error, @throw_state;
        END

        DECLARE @exists bit = 0;
        DECLARE @check_sql nvarchar(max) = N'
SELECT @exists = CASE WHEN EXISTS (
    SELECT 1
    FROM ' + QUOTENAME(@db) + N'.sys.objects AS o
    JOIN ' + QUOTENAME(@db) + N'.sys.schemas AS s ON s.schema_id = o.schema_id
    WHERE s.name = @schema
      AND o.name = @object
      AND o.type IN (''U'', ''V'')
) THEN 1 ELSE 0 END;';
        EXEC sp_executesql
            @check_sql,
            N'@schema nvarchar(128), @object nvarchar(128), @exists bit OUTPUT',
            @schema = @schema,
            @object = @object,
            @exists = @exists OUTPUT;

        IF @exists = 0
        BEGIN
            SET @error = CONCAT(N'tablename not found: ', @db, N'.', @schema, N'.', @object);
            SET @throw_number = 50026;
            ;THROW @throw_number, @error, @throw_state;
        END

        -- A table in {app}_proj is a system card. The business database is not.
        UPDATE dbo.api_card
        SET is_system = CASE WHEN @db = @main_db + N'_proj' THEN 1 ELSE 0 END
        WHERE id = @card_id
          AND is_system <> CASE WHEN @db = @main_db + N'_proj' THEN 1 ELSE 0 END;

        DROP TABLE IF EXISTS #cols;
        CREATE TABLE #cols (
            name       nvarchar(128) NOT NULL PRIMARY KEY,
            type_name  nvarchar(128) NOT NULL,
            max_length smallint      NOT NULL,
            precision  tinyint       NOT NULL,
            scale      tinyint       NOT NULL,
            type_decl  nvarchar(128) NULL
        );

        DECLARE @col_sql nvarchar(max) = N'
SELECT c.name, ty.name, c.max_length, c.precision, c.scale
FROM ' + QUOTENAME(@db) + N'.sys.columns AS c
JOIN ' + QUOTENAME(@db) + N'.sys.types AS ty ON ty.user_type_id = c.user_type_id
JOIN ' + QUOTENAME(@db) + N'.sys.objects AS o ON o.object_id = c.object_id
JOIN ' + QUOTENAME(@db) + N'.sys.schemas AS s ON s.schema_id = o.schema_id
WHERE s.name = @schema
  AND o.name = @object;';
        INSERT INTO #cols (name, type_name, max_length, precision, scale)
        EXEC sp_executesql
            @col_sql,
            N'@schema nvarchar(128), @object nvarchar(128)',
            @schema = @schema,
            @object = @object;

        UPDATE #cols
        SET type_decl = CASE type_name
            WHEN N'bigint' THEN N'bigint'
            WHEN N'int' THEN N'int'
            WHEN N'smallint' THEN N'smallint'
            WHEN N'tinyint' THEN N'tinyint'
            WHEN N'bit' THEN N'bit'
            WHEN N'float' THEN N'float'
            WHEN N'real' THEN N'real'
            WHEN N'date' THEN N'date'
            WHEN N'datetime' THEN N'datetime'
            WHEN N'datetime2' THEN N'datetime2'
            WHEN N'smalldatetime' THEN N'smalldatetime'
            WHEN N'datetimeoffset' THEN N'datetimeoffset'
            WHEN N'time' THEN N'time'
            WHEN N'uniqueidentifier' THEN N'uniqueidentifier'
            WHEN N'money' THEN N'money'
            WHEN N'smallmoney' THEN N'smallmoney'
            WHEN N'decimal' THEN CONCAT(N'decimal(', precision, N',', scale, N')')
            WHEN N'numeric' THEN CONCAT(N'numeric(', precision, N',', scale, N')')
            WHEN N'nvarchar' THEN CASE WHEN max_length < 0 THEN N'nvarchar(max)' ELSE CONCAT(N'nvarchar(', max_length / 2, N')') END
            WHEN N'nchar' THEN CONCAT(N'nchar(', CASE WHEN max_length < 0 THEN 1 ELSE max_length / 2 END, N')')
            WHEN N'varchar' THEN CASE WHEN max_length < 0 THEN N'varchar(max)' ELSE CONCAT(N'varchar(', max_length, N')') END
            WHEN N'char' THEN CONCAT(N'char(', CASE WHEN max_length < 0 THEN 1 ELSE max_length END, N')')
            WHEN N'varbinary' THEN CASE WHEN max_length < 0 THEN N'varbinary(max)' ELSE CONCAT(N'varbinary(', max_length, N')') END
            ELSE N'nvarchar(max)'
        END;

        IF NOT EXISTS (SELECT 1 FROM #cols WHERE name = @id_column)
        BEGIN
            SET @error = CONCAT(
                N'id_column "', @id_column, N'" was not found on ',
                @db, N'.', @schema, N'.', @object
            );
            SET @throw_number = 50027;
            ;THROW @throw_number, @error, @throw_state;
        END

        DECLARE @seed bit = 0;
        IF NOT EXISTS (SELECT 1 FROM dbo.api_card_fields WHERE card_id = @card_id)
            SET @seed = 1;

        DECLARE @bad_name nvarchar(128);
        SELECT TOP (1) @bad_name = f.name
        FROM dbo.api_card_fields AS f
        WHERE f.card_id = @card_id
          AND (
                f.name LIKE N'%[^A-Za-z0-9_]%'
             OR f.name LIKE N'[0-9]%'
             OR f.name = N''
          );
        IF @bad_name IS NOT NULL
        BEGIN
            SET @error = CONCAT(N'field "', @bad_name, N'" is not a plain identifier.');
            SET @throw_number = 50028;
            ;THROW @throw_number, @error, @throw_state;
        END

        DECLARE @bad_sql nvarchar(128);
        SELECT TOP (1) @bad_sql = f.name
        FROM dbo.api_card_fields AS f
        WHERE f.card_id = @card_id
          AND f.sql LIKE N'%;%';
        IF @bad_sql IS NOT NULL
        BEGIN
            SET @error = CONCAT(N'field "', @bad_sql, N'" sql must be one expression without a semicolon.');
            SET @throw_number = 50029;
            ;THROW @throw_number, @error, @throw_state;
        END

        DECLARE @bad_field nvarchar(128);
        SELECT TOP (1) @bad_field = f.name
        FROM dbo.api_card_fields AS f
        WHERE f.card_id = @card_id
          AND NULLIF(LTRIM(RTRIM(f.sql)), N'') IS NULL
          AND NOT EXISTS (SELECT 1 FROM #cols AS c WHERE c.name = f.name);
        IF @bad_field IS NOT NULL
        BEGIN
            SET @error = CONCAT(
                N'field "', @bad_field, N'" was not found on ',
                @db, N'.', @schema, N'.', @object,
                N' and has no sql expression'
            );
            SET @throw_number = 50030;
            ;THROW @throw_number, @error, @throw_state;
        END

        DROP TABLE IF EXISTS #use;
        CREATE TABLE #use (
            field_id     int            NULL,
            name         nvarchar(128)  NOT NULL,
            list_order   int            NOT NULL,
            detail_order int            NOT NULL,
            is_id        bit            NOT NULL,
            in_list      bit            NOT NULL,
            in_detail    bit            NOT NULL,
            type_decl    nvarchar(128)  NOT NULL,
            select_expr  nvarchar(max)  NOT NULL
        );

        IF @seed = 1
        BEGIN
            IF EXISTS (
                SELECT 1
                FROM #cols
                WHERE name LIKE N'%[^A-Za-z0-9_]%'
                   OR name LIKE N'[0-9]%'
            )
            BEGIN
                SET @error = N'A source column is not a plain identifier, so fields cannot be seeded.';
                SET @throw_number = 50031;
                ;THROW @throw_number, @error, @throw_state;
            END

            ;WITH numbered AS (
                SELECT
                    name,
                    type_decl,
                    ROW_NUMBER() OVER (ORDER BY name) AS ord
                FROM #cols
            )
            INSERT INTO #use (field_id, name, list_order, detail_order, is_id, in_list, in_detail, type_decl, select_expr)
            SELECT
                NULL,
                n.name,
                CASE WHEN n.name = @id_column THEN 0 ELSE n.ord * 2 END,
                CASE WHEN n.name = @id_column THEN 0 ELSE n.ord * 2 END,
                CASE WHEN n.name = @id_column THEN 1 ELSE 0 END,
                1,
                1,
                n.type_decl,
                N't.' + QUOTENAME(n.name)
            FROM numbered AS n;
        END
        ELSE
        BEGIN
            INSERT INTO #use (field_id, name, list_order, detail_order, is_id, in_list, in_detail, type_decl, select_expr)
            SELECT
                f.id,
                f.name,
                ISNULL(f.list_order, 0),
                ISNULL(f.detail_order, 0),
                CASE WHEN f.name = @id_column THEN 1 ELSE 0 END,
                CASE WHEN f.name = @id_column OR ISNULL(f.list_order, 0) > 0 THEN 1 ELSE 0 END,
                CASE WHEN f.name = @id_column OR ISNULL(f.detail_order, 0) > 0 THEN 1 ELSE 0 END,
                CASE
                    WHEN NULLIF(LTRIM(RTRIM(f.sql)), N'') IS NOT NULL THEN N'nvarchar(max)'
                    ELSE c.type_decl
                END,
                CASE
                    WHEN NULLIF(LTRIM(RTRIM(f.sql)), N'') IS NOT NULL THEN N'(' + f.sql + N')'
                    ELSE N't.' + QUOTENAME(f.name)
                END
            FROM dbo.api_card_fields AS f
            LEFT JOIN #cols AS c ON c.name = f.name
            WHERE f.card_id = @card_id;
        END

        IF NOT EXISTS (SELECT 1 FROM #use WHERE is_id = 1)
        BEGIN
            INSERT INTO #use (field_id, name, list_order, detail_order, is_id, in_list, in_detail, type_decl, select_expr)
            SELECT
                NULL,
                @id_column,
                0,
                0,
                1,
                1,
                1,
                c.type_decl,
                N't.' + QUOTENAME(@id_column)
            FROM #cols AS c
            WHERE c.name = @id_column;
        END

        DECLARE @from nvarchar(max) = N'FROM '
            + QUOTENAME(@db) + N'.' + QUOTENAME(@schema) + N'.' + QUOTENAME(@object)
            + N' AS t';
        DECLARE @list_where nvarchar(max) = N'WHERE (1 = 1)'
            + CASE WHEN @reducer IS NOT NULL THEN N' AND (' + @reducer + N')' ELSE N'' END;
        DECLARE @id_pred nvarchar(max) = N'WHERE t.' + QUOTENAME(@id_column) + N' = @' + @id_column;

        DECLARE @list_cols nvarchar(max);
        SELECT @list_cols = STRING_AGG(
            CAST(N'    ' + QUOTENAME(u.name) + N' = ' + u.select_expr AS nvarchar(max)),
            N',' + CHAR(10)
        ) WITHIN GROUP (ORDER BY u.is_id DESC, u.list_order, u.name)
        FROM #use AS u
        WHERE u.in_list = 1;

        DECLARE @detail_decl nvarchar(max);
        SELECT @detail_decl = STRING_AGG(
            CAST(N'DECLARE @' + u.name + N' ' + u.type_decl + N';' AS nvarchar(max)),
            CHAR(10)
        ) WITHIN GROUP (ORDER BY u.is_id DESC, u.detail_order, u.name)
        FROM #use AS u
        WHERE u.in_detail = 1;

        DECLARE @detail_assign nvarchar(max);
        SELECT @detail_assign = STRING_AGG(
            CAST(N'    @' + u.name + N' = ' + u.select_expr AS nvarchar(max)),
            N',' + CHAR(10)
        ) WITHIN GROUP (ORDER BY u.is_id DESC, u.detail_order, u.name)
        FROM #use AS u
        WHERE u.in_detail = 1;

        DECLARE @id_type nvarchar(128);
        SELECT @id_type = type_decl FROM #use WHERE is_id = 1;

        DECLARE @list_sql nvarchar(max) = N'SELECT' + CHAR(10)
            + @list_cols + CHAR(10)
            + @from + CHAR(10)
            + @list_where;

        DECLARE @select_sql nvarchar(max) = N'SET @' + @id_column
            + N' = TRY_CONVERT(' + @id_type + N', @id_text);' + CHAR(10)
            + N'SELECT' + CHAR(10)
            + @detail_assign + CHAR(10)
            + @from + CHAR(10)
            + @id_pred + N';';

        DECLARE @declare_sql nvarchar(max) = @detail_decl;

        DECLARE @list_check nvarchar(max) = N'
DROP TABLE IF EXISTS #list_probe;
SELECT *
INTO #list_probe
FROM (
' + REPLACE(@list_sql, N'WHERE (1 = 1)', N'WHERE (1 = 0)') + N'
) AS q;
DROP TABLE IF EXISTS #list_probe;';

        DECLARE @form_check nvarchar(max) = N'
DECLARE @id_text nvarchar(max) = NULL;
' + @declare_sql + CHAR(10)
            + REPLACE(@select_sql, @id_pred, N'WHERE (1 = 0)') + CHAR(10);

        BEGIN TRAN;
        EXEC sp_executesql @list_check;
        EXEC sp_executesql @form_check;

        UPDATE dbo.api_card
        SET list_select_cache = @list_sql,
            select_cache = @select_sql,
            declare_cache = @declare_sql,
            error = NULL
        WHERE id = @card_id;

        UPDATE f
        SET data_type = u.type_decl
        FROM dbo.api_card_fields AS f
        JOIN #use AS u ON u.field_id = f.id
        WHERE u.field_id IS NOT NULL;

        IF @seed = 1
        BEGIN
            INSERT INTO dbo.api_card_fields (
                card_id, name, display_name, list_order, detail_order, data_type
            )
            SELECT
                @card_id,
                u.name,
                u.name,
                u.list_order,
                u.detail_order,
                u.type_decl
            FROM #use AS u;
        END

        COMMIT TRAN;

        IF NOT EXISTS (
            SELECT 1
            FROM sys.objects
            WHERE name = @object
              AND schema_id = SCHEMA_ID(N'dbo')
              AND type <> 'SN'
        )
        BEGIN
            BEGIN TRY
                DECLARE @drop_syn nvarchar(max) = N'DROP SYNONYM IF EXISTS dbo.' + QUOTENAME(@object) + N';';
                DECLARE @make_syn nvarchar(max) = N'CREATE SYNONYM dbo.' + QUOTENAME(@object)
                    + N' FOR ' + QUOTENAME(@db) + N'.' + QUOTENAME(@schema) + N'.' + QUOTENAME(@object) + N';';
                EXEC sp_executesql @drop_syn;
                EXEC sp_executesql @make_syn;
            END TRY
            BEGIN CATCH
                -- The compiled SQL uses a three-part name, so a synonym miss is not fatal.
            END CATCH
        END

        IF @toast = 1
        BEGIN
            DECLARE @ok nvarchar(max) = N'Cache built';
            EXEC dbo.sp_api_toast @text = @ok;
        END
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRAN;

        SET @error = LEFT(ERROR_MESSAGE(), 2048);
        UPDATE dbo.api_card
        SET error = @error
        WHERE id = @card_id;

        IF @toast = 1
        BEGIN
            DECLARE @fail nvarchar(max) = CONCAT(N'Cache error: ', @error);
            EXEC dbo.sp_api_toast @text = @fail;
        END
        ;THROW;
    END CATCH
END
GO

-- Create an api_card from a table or view, then build its cache.
-- id_column: argument, else a column named id, else a one-column primary key, else an identity column.
CREATE OR ALTER PROCEDURE dbo.sp_api_card_from_table
    @table        nvarchar(256),
    @name         nvarchar(128) = NULL,
    @basetable    nvarchar(256) = NULL,
    @id_column    nvarchar(128) = NULL,
    @in_main_menu bit = 1,
    @record_limit int = 50,
    @sorting      nvarchar(512) = NULL,
    @card_id      int = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @error nvarchar(2048);
    DECLARE @throw_number int;
    DECLARE @throw_state int = 1;
    DECLARE @main nvarchar(128);
    DECLARE @raw_object nvarchar(128);
    DECLARE @raw_schema nvarchar(128);
    DECLARE @raw_db nvarchar(128);
    DECLARE @raw_extra nvarchar(128);
    DECLARE @db nvarchar(128);
    DECLARE @schema nvarchar(128);
    DECLARE @object nvarchar(128);
    DECLARE @obj_type nchar(2);
    DECLARE @meta nvarchar(max);
    DECLARE @cols nvarchar(max);
    DECLARE @pk_count int;
    DECLARE @pk_name nvarchar(128);
    DECLARE @card_name nvarchar(128);
    DECLARE @stored_table nvarchar(256);
    DECLARE @base_object nvarchar(128);
    DECLARE @base_schema nvarchar(128);
    DECLARE @base_db nvarchar(128);
    DECLARE @base_type nchar(2);
    DECLARE @toast bit;
    DECLARE @bad_col nvarchar(128);
    DECLARE @is_system bit;

    SET @card_id = NULL;
    SET @table = NULLIF(LTRIM(RTRIM(@table)), N'');
    SET @name = NULLIF(LTRIM(RTRIM(@name)), N'');
    SET @basetable = NULLIF(LTRIM(RTRIM(@basetable)), N'');
    SET @id_column = NULLIF(LTRIM(RTRIM(@id_column)), N'');
    SET @sorting = NULLIF(LTRIM(RTRIM(@sorting)), N'');
    SET @in_main_menu = ISNULL(@in_main_menu, 1);
    SET @main = dbo.main_db();

    IF @table IS NULL
    BEGIN
        SET @error = N'A table name is required.';
        SET @throw_number = 50040;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF @sorting LIKE N'%;%' OR @sorting LIKE N'%--%' OR @sorting LIKE N'%/*%'
    BEGIN
        SET @error = N'sorting must be a single expression.';
        SET @throw_number = 50041;
        ;THROW @throw_number, @error, @throw_state;
    END

    SET @raw_object = PARSENAME(@table, 1);
    SET @raw_schema = PARSENAME(@table, 2);
    SET @raw_db = PARSENAME(@table, 3);
    SET @raw_extra = PARSENAME(@table, 4);

    IF @raw_object IS NULL OR @raw_extra IS NOT NULL
    BEGIN
        SET @error = N'Table name could not be parsed. Use name, schema.name, or db.schema.name.';
        SET @throw_number = 50042;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF @raw_object LIKE N'%[^A-Za-z0-9_]%' OR @raw_object LIKE N'[0-9]%'
       OR @raw_schema LIKE N'%[^A-Za-z0-9_]%' OR @raw_schema LIKE N'[0-9]%'
       OR @raw_db LIKE N'%[^A-Za-z0-9_]%' OR @raw_db LIKE N'[0-9]%'
    BEGIN
        SET @error = N'Table name must use plain identifiers.';
        SET @throw_number = 50043;
        ;THROW @throw_number, @error, @throw_state;
    END

    SET @object = @raw_object;
    SET @schema = COALESCE(@raw_schema, N'dbo');
    SET @db = COALESCE(@raw_db, @main);

    SET @meta = N'
SELECT @obj_type = o.type
FROM ' + QUOTENAME(@db) + N'.sys.objects AS o
JOIN ' + QUOTENAME(@db) + N'.sys.schemas AS s ON s.schema_id = o.schema_id
WHERE s.name = @schema
  AND o.name = @object
  AND o.type IN (N''U'', N''V'');';
    EXEC sp_executesql
        @meta,
        N'@schema nvarchar(128), @object nvarchar(128), @obj_type nchar(2) OUTPUT',
        @schema = @schema,
        @object = @object,
        @obj_type = @obj_type OUTPUT;

    IF @obj_type IS NULL
    BEGIN
        SET @error = CONCAT(N'Table was not found: ', @db, N'.', @schema, N'.', @object);
        SET @throw_number = 50044;
        ;THROW @throw_number, @error, @throw_state;
    END

    DROP TABLE IF EXISTS #src;
    CREATE TABLE #src (
        name        nvarchar(128) NOT NULL PRIMARY KEY,
        column_id   int           NOT NULL,
        is_identity bit           NOT NULL,
        is_pk       bit           NOT NULL
    );

    SET @cols = N'
SELECT
    c.name,
    c.column_id,
    c.is_identity,
    CASE WHEN EXISTS (
        SELECT 1
        FROM ' + QUOTENAME(@db) + N'.sys.indexes AS i
        JOIN ' + QUOTENAME(@db) + N'.sys.index_columns AS ic
          ON ic.object_id = i.object_id
         AND ic.index_id = i.index_id
        WHERE i.is_primary_key = 1
          AND ic.object_id = c.object_id
          AND ic.column_id = c.column_id
          AND 1 = (
              SELECT COUNT(*)
              FROM ' + QUOTENAME(@db) + N'.sys.index_columns AS ic2
              WHERE ic2.object_id = i.object_id
                AND ic2.index_id = i.index_id
          )
    ) THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END
FROM ' + QUOTENAME(@db) + N'.sys.columns AS c
JOIN ' + QUOTENAME(@db) + N'.sys.objects AS o ON o.object_id = c.object_id
JOIN ' + QUOTENAME(@db) + N'.sys.schemas AS s ON s.schema_id = o.schema_id
WHERE s.name = @schema
  AND o.name = @object;';
    INSERT INTO #src (name, column_id, is_identity, is_pk)
    EXEC sp_executesql
        @cols,
        N'@schema nvarchar(128), @object nvarchar(128)',
        @schema = @schema,
        @object = @object;

    SELECT TOP (1) @bad_col = name
    FROM #src
    WHERE name LIKE N'%[^A-Za-z0-9_]%'
       OR name LIKE N'[0-9]%';
    IF @bad_col IS NOT NULL
    BEGIN
        SET @error = N'A source column is not a plain identifier, so fields cannot be seeded.';
        SET @throw_number = 50045;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF @id_column IS NULL AND EXISTS (SELECT 1 FROM #src WHERE name = N'id')
        SET @id_column = N'id';

    IF @id_column IS NULL
    BEGIN
        SELECT @pk_count = COUNT(*), @pk_name = MIN(name)
        FROM #src
        WHERE is_pk = 1;
        IF @pk_count = 1
            SET @id_column = @pk_name;
    END

    IF @id_column IS NULL
        SELECT TOP (1) @id_column = name
        FROM #src
        WHERE is_identity = 1
        ORDER BY column_id;

    IF @id_column IS NULL
    BEGIN
        SET @error = N'The source has no id column. Pass @id_column.';
        SET @throw_number = 50046;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF @id_column LIKE N'%[^A-Za-z0-9_]%' OR @id_column LIKE N'[0-9]%'
    BEGIN
        SET @error = N'id_column must be a plain identifier.';
        SET @throw_number = 50047;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF NOT EXISTS (SELECT 1 FROM #src WHERE name = @id_column)
    BEGIN
        SET @error = CONCAT(
            N'id_column "', @id_column, N'" was not found on ',
            @db, N'.', @schema, N'.', @object
        );
        SET @throw_number = 50048;
        ;THROW @throw_number, @error, @throw_state;
    END

    SET @card_name = COALESCE(@name, @object);
    IF @card_name LIKE N'%[^A-Za-z0-9_]%' OR @card_name LIKE N'[0-9]%'
    BEGIN
        SET @error = N'Card name must be a plain identifier.';
        SET @throw_number = 50049;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF EXISTS (SELECT 1 FROM dbo.api_card WHERE name = @card_name)
    BEGIN
        SET @error = CONCAT(N'A card named ', @card_name, N' already exists.');
        SET @throw_number = 50050;
        ;THROW @throw_number, @error, @throw_state;
    END

    IF @basetable IS NOT NULL
    BEGIN
        SET @base_object = PARSENAME(@basetable, 1);
        SET @base_schema = COALESCE(PARSENAME(@basetable, 2), N'dbo');
        SET @base_db = COALESCE(PARSENAME(@basetable, 3), @main);
        IF @base_object IS NULL
           OR PARSENAME(@basetable, 4) IS NOT NULL
           OR @base_object LIKE N'%[^A-Za-z0-9_]%' OR @base_object LIKE N'[0-9]%'
           OR @base_schema LIKE N'%[^A-Za-z0-9_]%' OR @base_schema LIKE N'[0-9]%'
           OR @base_db LIKE N'%[^A-Za-z0-9_]%' OR @base_db LIKE N'[0-9]%'
        BEGIN
            SET @error = N'basetable must be a plain table name.';
            SET @throw_number = 50051;
            ;THROW @throw_number, @error, @throw_state;
        END
        IF @base_db <> @main OR @base_schema <> N'dbo'
        BEGIN
            SET @error = N'basetable must be a table in the main database dbo, so the form can save.';
            SET @throw_number = 50052;
            ;THROW @throw_number, @error, @throw_state;
        END

        SET @meta = N'
SELECT @base_type = o.type
FROM ' + QUOTENAME(@base_db) + N'.sys.objects AS o
JOIN ' + QUOTENAME(@base_db) + N'.sys.schemas AS s ON s.schema_id = o.schema_id
WHERE s.name = @schema
  AND o.name = @object
  AND o.type = N''U'';';
        EXEC sp_executesql
            @meta,
            N'@schema nvarchar(128), @object nvarchar(128), @base_type nchar(2) OUTPUT',
            @schema = @base_schema,
            @object = @base_object,
            @base_type = @base_type OUTPUT;
        IF @base_type IS NULL
        BEGIN
            SET @error = CONCAT(N'basetable was not found: ', @base_db, N'.', @base_schema, N'.', @base_object);
            SET @throw_number = 50053;
            ;THROW @throw_number, @error, @throw_state;
        END
        SET @basetable = @base_object;
    END
    ELSE IF @obj_type = N'U' AND @db = @main AND @schema = N'dbo'
        SET @basetable = @object;

    IF @db = @main AND @schema = N'dbo'
        SET @stored_table = @object;
    ELSE IF @db = @main
        SET @stored_table = @schema + N'.' + @object;
    ELSE
        SET @stored_table = @db + N'.' + @schema + N'.' + @object;
    SET @is_system = CASE WHEN @db = @main + N'_proj' THEN 1 ELSE 0 END;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @new_id TABLE (id int NOT NULL);
        INSERT INTO dbo.api_card (
            name, tablename, basetable, id_column,
            in_main_menu, record_limit, sorting_order, is_system
        )
        OUTPUT inserted.id INTO @new_id (id)
        VALUES (
            @card_name, @stored_table, @basetable, @id_column,
            @in_main_menu, @record_limit, @sorting, @is_system
        );
        SELECT @card_id = id FROM @new_id;

        SET @toast = 0;
        EXEC dbo.sp_api_card_create_cache @card_id = @card_id, @toast = @toast;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRAN;
        SET @card_id = NULL;
        ;THROW;
    END CATCH
END
GO
