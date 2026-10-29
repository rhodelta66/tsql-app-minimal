USE demo_proj;
GO

CREATE OR ALTER FUNCTION dbo.main_db()
RETURNS nvarchar(128)
AS
BEGIN
    DECLARE @name nvarchar(128) = CONVERT(nvarchar(128), SESSION_CONTEXT(N'main_db'));
    IF @name IS NULL OR LTRIM(RTRIM(@name)) = N''
    BEGIN
        DECLARE @current nvarchar(128) = DB_NAME();
        IF RIGHT(@current, 5) = N'_proj' AND LEN(@current) > 5
            SET @name = LEFT(@current, LEN(@current) - 5);
        ELSE
            SET @name = @current;
    END
    RETURN @name;
END
GO

CREATE OR ALTER FUNCTION dbo.fn_split_declare(@src nvarchar(max))
RETURNS @items TABLE (
    item nvarchar(400) NOT NULL,
    ord  int NOT NULL
)
AS
BEGIN
    IF @src IS NULL OR LTRIM(RTRIM(@src)) = N''
        RETURN;

    DECLARE @i int = 1;
    DECLARE @n int = LEN(@src);
    DECLARE @start int = 1;
    DECLARE @depth int = 0;
    DECLARE @ord int = 0;
    DECLARE @ch nchar(1);

    WHILE @i <= @n
    BEGIN
        SET @ch = SUBSTRING(@src, @i, 1);
        IF @ch = N'('
            SET @depth = @depth + 1;
        ELSE IF @ch = N')' AND @depth > 0
            SET @depth = @depth - 1;
        ELSE IF @ch = N',' AND @depth = 0
        BEGIN
            SET @ord = @ord + 1;
            INSERT INTO @items (item, ord)
            VALUES (LTRIM(RTRIM(SUBSTRING(@src, @start, @i - @start))), @ord);
            SET @start = @i + 1;
        END
        SET @i = @i + 1;
    END

    SET @ord = @ord + 1;
    INSERT INTO @items (item, ord)
    VALUES (LTRIM(RTRIM(SUBSTRING(@src, @start, @n - @start + 1))), @ord);

    DELETE FROM @items WHERE item = N'';
    RETURN;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_require_session
    @session_id int OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET @session_id = TRY_CONVERT(int, SESSION_CONTEXT(N'session_id'));
    IF @session_id IS NULL
        THROW 50001, N'No session. Call sp_api_request.', 1;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_ensure_state
    @session_id int
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.api_modal_state WHERE session_id = @session_id)
    BEGIN
        INSERT INTO dbo.api_modal_state (session_id, is_open, clear_requested)
        VALUES (@session_id, 0, 0);
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_emit
    @session_id int,
    @kind       nvarchar(32),
    @payload    nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @seq int;
    SELECT @seq = ISNULL(MAX(seq), 0) + 1
    FROM dbo.api_modal_render WITH (UPDLOCK, HOLDLOCK)
    WHERE session_id = @session_id;

    INSERT INTO dbo.api_modal_render (session_id, seq, kind, payload)
    VALUES (@session_id, @seq, @kind, @payload);
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_get_value
    @name  nvarchar(128),
    @value nvarchar(max) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int;
    EXEC dbo.sp_api_require_session @session_id = @session_id OUTPUT;

    SET @value = NULL;
    SELECT @value = p.value
    FROM dbo.api_modal_post AS p
    WHERE p.session_id = @session_id
      AND p.name = @name;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_get
    @name  nvarchar(128),
    @value nvarchar(max) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int;
    EXEC dbo.sp_api_require_session @session_id = @session_id OUTPUT;

    SET @value = NULL;
    SELECT @value = s.value
    FROM dbo.api_session_storage AS s
    WHERE s.session_id = @session_id
      AND s.name = @name;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_set
    @name  nvarchar(128),
    @value nvarchar(max) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int;
    EXEC dbo.sp_api_require_session @session_id = @session_id OUTPUT;

    IF @value IS NULL
    BEGIN
        DELETE FROM dbo.api_session_storage
        WHERE session_id = @session_id
          AND name = @name;
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.api_session_storage
        WHERE session_id = @session_id
          AND name = @name
    )
    BEGIN
        UPDATE dbo.api_session_storage
        SET value = @value
        WHERE session_id = @session_id
          AND name = @name;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.api_session_storage (session_id, name, value)
        VALUES (@session_id, @name, @value);
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_toast
    @text  nvarchar(max),
    @class nvarchar(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int = TRY_CONVERT(int, SESSION_CONTEXT(N'session_id'));
    IF @session_id IS NULL OR @text IS NULL
        RETURN;

    INSERT INTO dbo.api_toast (session_id, text, css_class)
    VALUES (@session_id, @text, @class);
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_modal
    @class nvarchar(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int;
    EXEC dbo.sp_api_require_session @session_id = @session_id OUTPUT;
    EXEC dbo.sp_api_modal_ensure_state @session_id = @session_id;

    DECLARE @action_id int = TRY_CONVERT(int, SESSION_CONTEXT(N'action_id'));
    DECLARE @path nvarchar(400) = CONVERT(nvarchar(400), SESSION_CONTEXT(N'path'));

    UPDATE dbo.api_modal_state
    SET is_open = 1,
        clear_requested = 0,
        css_class = @class,
        action_id = COALESCE(@action_id, action_id),
        path = COALESCE(@path, path)
    WHERE session_id = @session_id;

    DECLARE @payload nvarchar(max);
    SET @payload = (
        SELECT
            N'modal' AS kind,
            @class AS class
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );
    EXEC dbo.sp_api_modal_emit
        @session_id = @session_id,
        @kind = N'modal',
        @payload = @payload;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_clear
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int;
    EXEC dbo.sp_api_require_session @session_id = @session_id OUTPUT;
    EXEC dbo.sp_api_modal_ensure_state @session_id = @session_id;

    -- clear does not stop the batch. The caller must RETURN, or a later
    -- sp_api_modal_modal paints the dialog again.
    UPDATE dbo.api_modal_state
    SET is_open = 0,
        clear_requested = 1,
        action_id = NULL,
        css_class = NULL
    WHERE session_id = @session_id;

    DELETE FROM dbo.api_modal_post WHERE session_id = @session_id;
    DELETE FROM dbo.api_modal_render WHERE session_id = @session_id;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_text
    @text  nvarchar(max),
    @class nvarchar(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int;
    EXEC dbo.sp_api_require_session @session_id = @session_id OUTPUT;

    DECLARE @payload nvarchar(max);
    SET @payload = (
        SELECT
            N'text' AS kind,
            @text AS text,
            @class AS class
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );
    EXEC dbo.sp_api_modal_emit
        @session_id = @session_id,
        @kind = N'text',
        @payload = @payload;
END
GO

-- A caption is a parameter of the input, not its own procedure.
DROP PROCEDURE IF EXISTS dbo.sp_api_modal_label;
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_input
    @name        nvarchar(128),
    @value       nvarchar(max) = NULL OUTPUT,
    @type        nvarchar(32) = N'text',
    @placeholder nvarchar(256) = NULL,
    @focus       bit = 0,
    @label       nvarchar(256) = NULL,
    @options     nvarchar(max) = NULL,
    @multiple    bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int;
    EXEC dbo.sp_api_require_session @session_id = @session_id OUTPUT;

    DECLARE @posted nvarchar(max);
    DECLARE @has_post bit = 0;
    SELECT
        @posted = p.value,
        @has_post = 1
    FROM dbo.api_modal_post AS p
    WHERE p.session_id = @session_id
      AND p.name = @name;

    IF @has_post = 1
        SET @value = @posted;

    -- Options are a comma list, or a JSON array of strings or {id, name}.
    -- The client receives one array either way.
    DECLARE @options_json nvarchar(max) = NULL;
    IF @options IS NOT NULL AND LTRIM(RTRIM(@options)) <> N''
    BEGIN
        IF ISJSON(@options) = 1 AND LEFT(LTRIM(@options), 1) = N'['
        BEGIN
            SELECT @options_json = (
                SELECT
                    COALESCE(
                        JSON_VALUE(j.value, '$.id'),
                        CASE WHEN j.[type] = 1 THEN j.value END
                    ) AS id,
                    COALESCE(
                        JSON_VALUE(j.value, '$.name'),
                        JSON_VALUE(j.value, '$.id'),
                        CASE WHEN j.[type] = 1 THEN j.value END
                    ) AS name
                FROM OPENJSON(@options) AS j
                FOR JSON PATH
            );
        END
        ELSE
        BEGIN
            SELECT @options_json = (
                SELECT
                    LTRIM(RTRIM(s.value)) AS id,
                    LTRIM(RTRIM(s.value)) AS name
                FROM STRING_SPLIT(@options, N',', 1) AS s
                WHERE LTRIM(RTRIM(s.value)) <> N''
                ORDER BY s.ordinal
                FOR JSON PATH
            );
        END
    END

    DECLARE @payload nvarchar(max);
    SET @payload = (
        SELECT
            N'input' AS kind,
            @name AS name,
            @type AS type,
            @value AS value,
            @placeholder AS placeholder,
            CAST(@focus AS bit) AS focus,
            @label AS label,
            JSON_QUERY(@options_json) AS options,
            CAST(ISNULL(@multiple, 0) AS bit) AS multiple
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );
    EXEC dbo.sp_api_modal_emit
        @session_id = @session_id,
        @kind = N'input',
        @payload = @payload;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_api_modal_button
    @name  nvarchar(128),
    @value nvarchar(max) = NULL,
    @out   nvarchar(max) = NULL OUTPUT,
    @class nvarchar(128) = NULL,
    @key   nvarchar(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @session_id int;
    EXEC dbo.sp_api_require_session @session_id = @session_id OUTPUT;

    -- Capture the click, then wipe the posted slot. A get_value that runs
    -- after this render no longer sees the click. Read before render.
    DECLARE @posted nvarchar(max);
    DECLARE @has_post bit = 0;
    SELECT
        @posted = p.value,
        @has_post = 1
    FROM dbo.api_modal_post AS p
    WHERE p.session_id = @session_id
      AND p.name = @name;

    IF @has_post = 1 AND @posted IS NOT NULL
        SET @out = @value;
    ELSE
        SET @out = NULL;

    UPDATE dbo.api_modal_post
    SET value = NULL
    WHERE session_id = @session_id
      AND name = @name;

    DECLARE @payload nvarchar(max);
    SET @payload = (
        SELECT
            N'button' AS kind,
            @name AS name,
            @value AS value,
            @class AS class,
            @key AS [key]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
    );
    EXEC dbo.sp_api_modal_emit
        @session_id = @session_id,
        @kind = N'button',
        @payload = @payload;
END
GO
