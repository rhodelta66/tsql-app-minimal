USE demo;
GO

DROP VIEW IF EXISTS dbo.v_customer;
GO
DROP TABLE IF EXISTS dbo.customer_note;
GO
DROP TABLE IF EXISTS dbo.customer;
GO

CREATE TABLE dbo.customer (
    id             int IDENTITY(1,1) NOT NULL CONSTRAINT pk_customer PRIMARY KEY,
    customer_name  nvarchar(200) NOT NULL,
    status         nvarchar(32)  NOT NULL,
    city           nvarchar(100) NULL,
    credit_limit   decimal(18, 2) NOT NULL CONSTRAINT df_customer_credit DEFAULT (0)
);
GO

CREATE TABLE dbo.customer_note (
    id           int IDENTITY(1,1) NOT NULL CONSTRAINT pk_customer_note PRIMARY KEY,
    customer_id  int NULL,
    note         nvarchar(200) NOT NULL,
    created_at   datetime2 NOT NULL CONSTRAINT df_customer_note_created DEFAULT (SYSUTCDATETIME())
);
GO

CREATE VIEW dbo.v_customer
AS
SELECT
    c.id,
    c.customer_name,
    c.status,
    c.city,
    c.credit_limit
FROM dbo.customer AS c;
GO

INSERT INTO dbo.customer (customer_name, status, city, credit_limit)
VALUES
    (N'Ada Lovegrove', N'open', N'Amsterdam', 1200.50),
    (N'Ben Hart', N'closed', N'Rotterdam', 50.00),
    (N'Chi Ortega', N'open', N'Utrecht', 800.00);
GO

USE demo_proj;
GO

CREATE OR ALTER PROCEDURE dbo.sp_example_minimal_modal
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @btn_save nvarchar(128);
    DECLARE @my_value nvarchar(200);
    DECLARE @record_id nvarchar(32);
    DECLARE @customer_key int;
    DECLARE @note nvarchar(200);
    DECLARE @save_name nvarchar(128);
    DECLARE @value_name nvarchar(128);
    DECLARE @warn nvarchar(200);
    DECLARE @saved nvarchar(200);
    DECLARE @heading nvarchar(200);
    DECLARE @heading_class nvarchar(32);
    DECLARE @input_type nvarchar(32);
    DECLARE @placeholder nvarchar(200);
    DECLARE @btn_value nvarchar(128);
    DECLARE @btn_class nvarchar(128);

    SET @record_id = CONVERT(nvarchar(32), SESSION_CONTEXT(N'id'));
    SET @save_name = N'@btn_save';
    SET @value_name = N'@my_value';

    -- READ before RENDER. A later button render consumes the click.
    EXEC dbo.sp_api_modal_get_value @name = @save_name, @value = @btn_save OUT;
    EXEC dbo.sp_api_modal_get_value @name = @value_name, @value = @my_value OUT;

    IF @btn_save IS NOT NULL
    BEGIN
        IF ISNULL(@my_value, N'') = N''
        BEGIN
            SET @warn = N'Value is required';
            EXEC dbo.sp_api_toast @text = @warn;
        END
        ELSE
        BEGIN
            SET @note = @my_value;
            SET @customer_key = TRY_CONVERT(int, @record_id);
            INSERT INTO demo.dbo.customer_note (customer_id, note)
            VALUES (@customer_key, @note);

            EXEC dbo.sp_api_modal_clear;
            SET @saved = N'Saved successfully';
            EXEC dbo.sp_api_toast @text = @saved;
            RETURN;
        END
    END

    EXEC dbo.sp_api_modal_modal;
    SET @heading = N'Minimal Modal Example';
    SET @heading_class = N'h3';
    EXEC dbo.sp_api_modal_text @text = @heading, @class = @heading_class;
    SET @input_type = N'text';
    SET @placeholder = N'Enter a value...';
    EXEC dbo.sp_api_modal_input
        @name = @value_name,
        @value = @my_value OUT,
        @type = @input_type,
        @placeholder = @placeholder;
    SET @btn_value = N'Save';
    SET @btn_class = N'btn-primary';
    EXEC dbo.sp_api_modal_button
        @name = @save_name,
        @value = @btn_value,
        @out = @btn_save OUT,
        @class = @btn_class;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_example_wizard
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @step nvarchar(10);
    DECLARE @name nvarchar(200);
    DECLARE @email nvarchar(200);
    DECLARE @btn_next nvarchar(128);
    DECLARE @btn_back nvarchar(128);
    DECLARE @btn_save nvarchar(128);
    DECLARE @stored_name nvarchar(200);
    DECLARE @step_key nvarchar(128);
    DECLARE @name_key nvarchar(128);
    DECLARE @name_post nvarchar(128);
    DECLARE @email_post nvarchar(128);
    DECLARE @next_name nvarchar(128);
    DECLARE @back_name nvarchar(128);
    DECLARE @save_name nvarchar(128);
    DECLARE @need_name nvarchar(200);
    DECLARE @need_email nvarchar(200);
    DECLARE @danger nvarchar(32);
    DECLARE @success nvarchar(32);
    DECLARE @step1 nvarchar(10);
    DECLARE @step2 nvarchar(10);
    DECLARE @record_id nvarchar(32);
    DECLARE @customer_key int;
    DECLARE @note nvarchar(200);
    DECLARE @clear_value nvarchar(max);
    DECLARE @done nvarchar(200);
    DECLARE @h1 nvarchar(200);
    DECLARE @h2 nvarchar(200);
    DECLARE @hclass nvarchar(32);
    DECLARE @who nvarchar(400);
    DECLARE @who_class nvarchar(32);
    DECLARE @input_type nvarchar(32);
    DECLARE @name_ph nvarchar(200);
    DECLARE @email_ph nvarchar(200);
    DECLARE @next_value nvarchar(128);
    DECLARE @back_value nvarchar(128);
    DECLARE @save_value nvarchar(128);
    DECLARE @primary_class nvarchar(128);
    DECLARE @back_class nvarchar(128);
    DECLARE @enter_key nvarchar(32);

    SET @step_key = N'wizard_step';
    SET @name_key = N'wizard_name';
    SET @name_post = N'@name';
    SET @email_post = N'@email';
    SET @next_name = N'@btn_next';
    SET @back_name = N'@btn_back';
    SET @save_name = N'@btn_save';
    SET @danger = N'text-danger';
    SET @success = N'text-success';
    SET @step1 = N'1';
    SET @step2 = N'2';
    SET @hclass = N'h3';
    SET @who_class = N'text';
    SET @input_type = N'text';
    SET @primary_class = N'btn-primary';
    SET @back_class = N'btn-secondary';
    SET @enter_key = N'Enter';

    EXEC dbo.sp_api_modal_get @name = @step_key, @value = @step OUTPUT;
    EXEC dbo.sp_api_modal_get @name = @name_key, @value = @stored_name OUTPUT;
    EXEC dbo.sp_api_modal_get_value @name = @name_post, @value = @name OUTPUT;
    EXEC dbo.sp_api_modal_get_value @name = @email_post, @value = @email OUTPUT;
    EXEC dbo.sp_api_modal_get_value @name = @next_name, @value = @btn_next OUTPUT;
    EXEC dbo.sp_api_modal_get_value @name = @back_name, @value = @btn_back OUTPUT;
    EXEC dbo.sp_api_modal_get_value @name = @save_name, @value = @btn_save OUTPUT;

    IF @step IS NULL
        SET @step = @step1;

    IF @btn_next IS NOT NULL AND @step = @step1
    BEGIN
        IF ISNULL(@name, N'') = N''
        BEGIN
            SET @need_name = N'Name is required';
            EXEC dbo.sp_api_toast @text = @need_name, @class = @danger;
        END
        ELSE
        BEGIN
            EXEC dbo.sp_api_modal_set @name = @name_key, @value = @name;
            EXEC dbo.sp_api_modal_set @name = @step_key, @value = @step2;
            SET @stored_name = @name;
            SET @step = @step2;
        END
    END

    IF @btn_back IS NOT NULL AND @step = @step2
    BEGIN
        EXEC dbo.sp_api_modal_set @name = @step_key, @value = @step1;
        SET @step = @step1;
        SET @name = @stored_name;
    END

    IF @btn_save IS NOT NULL AND @step = @step2
    BEGIN
        IF ISNULL(@email, N'') = N''
        BEGIN
            SET @need_email = N'Email is required';
            EXEC dbo.sp_api_toast @text = @need_email, @class = @danger;
        END
        ELSE
        BEGIN
            SET @record_id = CONVERT(nvarchar(32), SESSION_CONTEXT(N'id'));
            SET @customer_key = TRY_CONVERT(int, @record_id);
            SET @note = CONCAT(@stored_name, N' <', @email, N'>');
            INSERT INTO demo.dbo.customer_note (customer_id, note)
            VALUES (@customer_key, @note);

            SET @clear_value = NULL;
            EXEC dbo.sp_api_modal_set @name = @name_key, @value = @clear_value;
            EXEC dbo.sp_api_modal_set @name = @step_key, @value = @clear_value;
            EXEC dbo.sp_api_modal_clear;
            SET @done = N'Wizard saved';
            EXEC dbo.sp_api_toast @text = @done, @class = @success;
            RETURN;
        END
    END

    EXEC dbo.sp_api_modal_modal;

    IF @step = @step1
    BEGIN
        SET @h1 = N'Step 1 - name';
        EXEC dbo.sp_api_modal_text @text = @h1, @class = @hclass;
        IF @name IS NULL
            SET @name = @stored_name;
        SET @name_ph = N'Name';
        EXEC dbo.sp_api_modal_input
            @name = @name_post,
            @value = @name OUTPUT,
            @type = @input_type,
            @placeholder = @name_ph;
        SET @next_value = N'Next';
        EXEC dbo.sp_api_modal_button
            @name = @next_name,
            @value = @next_value,
            @out = @btn_next OUTPUT,
            @class = @primary_class,
            @key = @enter_key;
    END
    ELSE
    BEGIN
        SET @h2 = N'Step 2 - email';
        EXEC dbo.sp_api_modal_text @text = @h2, @class = @hclass;
        SET @who = CONCAT(N'Name: ', @stored_name);
        EXEC dbo.sp_api_modal_text @text = @who, @class = @who_class;
        SET @email_ph = N'Email';
        EXEC dbo.sp_api_modal_input
            @name = @email_post,
            @value = @email OUTPUT,
            @type = @input_type,
            @placeholder = @email_ph;
        SET @back_value = N'Back';
        EXEC dbo.sp_api_modal_button
            @name = @back_name,
            @value = @back_value,
            @out = @btn_back OUTPUT,
            @class = @back_class;
        SET @save_value = N'Save';
        EXEC dbo.sp_api_modal_button
            @name = @save_name,
            @value = @save_value,
            @out = @btn_save OUTPUT,
            @class = @primary_class,
            @key = @enter_key;
    END
END
GO

DELETE FROM dbo.api_card_actions;
DELETE FROM dbo.api_card;
GO

INSERT INTO dbo.api_card (
    name, tablename, basetable, id_column,
    in_main_menu, menu_keycode, record_limit, sorting_order
)
VALUES (
    N'customer', N'v_customer', N'customer', N'id',
    1, N'C', 50, N'customer_name'
);
GO

DECLARE @card_id int = (SELECT id FROM dbo.api_card WHERE name = N'customer');

INSERT INTO dbo.api_card_fields (card_id, name, display_name, list_order, detail_order, list_class)
VALUES
    (@card_id, N'id', N'ID', 0, 0, NULL),
    (@card_id, N'customer_name', N'Customer name', 2, 2, NULL),
    (@card_id, N'status', N'Status', 4, 4, NULL),
    (@card_id, N'city', N'City', 6, 6, NULL),
    (@card_id, N'credit_limit', N'Credit limit', 8, 8, N'text-end');

INSERT INTO dbo.api_card_fields (card_id, name, display_name, list_order, detail_order, sql)
VALUES (
    @card_id,
    N'place_label',
    N'Place',
    10,
    0,
    N'CONCAT(customer_name, N'' - '', city)'
);

INSERT INTO dbo.api_card_actions (
    card_id, name, display_name, action, sql, type, keycode, action_order
)
VALUES
    (
        @card_id,
        N'sp_example_minimal_modal',
        N'Note',
        N'stored_procedure',
        N'EXEC dbo.sp_example_minimal_modal',
        N'list_form',
        N'Alt+N',
        10
    ),
    (
        @card_id,
        N'sp_example_wizard',
        N'Wizard',
        N'stored_procedure',
        N'EXEC dbo.sp_example_wizard',
        N'list_form',
        N'Alt+W',
        20
    ),
    (
        @card_id,
        N'hello',
        N'Hello',
        N'stored_procedure',
        N'DECLARE @btn_ok nvarchar(128);
DECLARE @btn_name nvarchar(128);
DECLARE @heading nvarchar(400);
DECLARE @heading_class nvarchar(32);
DECLARE @btn_value nvarchar(128);
DECLARE @btn_class nvarchar(128);
DECLARE @customer_id int;
DECLARE @customer_name nvarchar(200);
DECLARE @missing nvarchar(200);
DECLARE @toast_class nvarchar(128);
SET @btn_name = N''@btn_ok'';
EXEC dbo.sp_api_modal_get_value @name = @btn_name, @value = @btn_ok OUT;
IF @btn_ok IS NOT NULL
BEGIN
    EXEC dbo.sp_api_modal_clear;
    RETURN;
END
SET @customer_id = TRY_CONVERT(int, @id);
SELECT @customer_name = c.customer_name
FROM demo.dbo.customer AS c
WHERE c.id = @customer_id;
IF @customer_name IS NULL OR LTRIM(RTRIM(@customer_name)) = N''''
BEGIN
    SET @missing = N''Choose a customer.'';
    SET @toast_class = N''text-danger'';
    EXEC dbo.sp_api_toast @text = @missing, @class = @toast_class;
    RETURN;
END
EXEC dbo.sp_api_modal_modal;
SET @heading = N''hello '' + @customer_name;
SET @heading_class = N''h1'';
EXEC dbo.sp_api_modal_text @text = @heading, @class = @heading_class;
SET @btn_value = N''OK'';
SET @btn_class = N''btn-primary'';
EXEC dbo.sp_api_modal_button
    @name = @btn_name,
    @value = @btn_value,
    @out = @btn_ok OUT,
    @class = @btn_class;',
        N'list_form',
        NULL,
        30
    ),
    (
        @card_id,
        N'label',
        N'Label',
        N'stored_procedure',
        N'DECLARE @heading nvarchar(200);
DECLARE @hclass nvarchar(32);
DECLARE @caption nvarchar(200);
DECLARE @field nvarchar(128);
DECLARE @fname nvarchar(max);
DECLARE @input_type nvarchar(32);
DECLARE @submit_name nvarchar(128);
DECLARE @submit_value nvarchar(200);
DECLARE @submit nvarchar(max);
DECLARE @toast nvarchar(200);
DECLARE @toast_class nvarchar(128);
SET @field = N''fname'';
SET @submit_name = N''submit'';
SET @heading = N''The input Element'';
SET @hclass = N''h2'';
SET @caption = N''First name:'';
SET @input_type = N''text'';
SET @submit_value = N''Submit'';
EXEC dbo.sp_api_modal_get_value @name = @field, @value = @fname OUTPUT;
EXEC dbo.sp_api_modal_get_value @name = @submit_name, @value = @submit OUTPUT;
IF @submit IS NOT NULL
BEGIN
    IF @fname IS NULL OR LTRIM(RTRIM(@fname)) = N''''
    BEGIN
        SET @toast = N''First name is required'';
        SET @toast_class = N''text-danger'';
        EXEC dbo.sp_api_toast @text = @toast, @class = @toast_class;
    END
    ELSE
    BEGIN
        SET @toast = CONCAT(N''First name: '', @fname);
        SET @toast_class = N''text-success'';
        EXEC dbo.sp_api_toast @text = @toast, @class = @toast_class;
        EXEC dbo.sp_api_modal_clear;
        RETURN;
    END
END
EXEC dbo.sp_api_modal_modal;
EXEC dbo.sp_api_modal_text @text = @heading, @class = @hclass;
EXEC dbo.sp_api_modal_input
    @name = @field,
    @value = @fname OUTPUT,
    @type = @input_type,
    @label = @caption;
EXEC dbo.sp_api_modal_button
    @name = @submit_name,
    @value = @submit_value,
    @out = @submit OUTPUT;',
        N'list_form',
        N'Alt+L',
        40
    );

EXEC dbo.sp_api_card_create_cache @card_id = @card_id, @toast = 1;
GO
