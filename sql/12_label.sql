-- Label example on the customer card. Safe to re-run.
-- Inserts the button only when the action name is absent.
-- Does not change Hello, Note, Wizard, or an edited Label row.
-- Does not drop a database, a card, or a business row.
USE demo_proj;
GO

DECLARE @card_id int = (SELECT id FROM dbo.api_card WHERE name = N'customer');
DECLARE @sql nvarchar(max) = N'DECLARE @heading nvarchar(200);
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
    @out = @submit OUTPUT;';

IF @card_id IS NULL
    THROW 50000, N'customer card is missing.', 1;

IF NOT EXISTS (
    SELECT 1
    FROM dbo.api_card_actions
    WHERE card_id = @card_id
      AND name = N'label'
)
BEGIN
    INSERT INTO dbo.api_card_actions (
        card_id, name, display_name, action, sql, type, keycode, action_order
    )
    VALUES (
        @card_id,
        N'label',
        N'Label',
        N'stored_procedure',
        @sql,
        N'list_form',
        N'Alt+L',
        40
    );
END
GO
