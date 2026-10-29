USE demo_proj;
GO

-- Metadata cards. Re-running deletes and recreates only ide, ide_field, and ide_action.
SET NOCOUNT ON;

DECLARE @toast bit;
DECLARE @ide int;
DECLARE @ide_field int;
DECLARE @ide_action int;
DECLARE @card_name_sql nvarchar(max);

SET @card_name_sql = N'(SELECT c.name FROM dbo.api_card AS c WHERE c.id = t.card_id)';

DELETE FROM dbo.api_card WHERE name IN (N'ide', N'ide_field', N'ide_action');

INSERT INTO dbo.api_card (
    name, tablename, basetable, id_column, in_main_menu, menu_keycode, record_limit, sorting_order, ide_role, is_system
)
VALUES
    (N'ide', N'demo_proj.dbo.api_card', N'api_card', N'id', 1, N'I', 200, N'name', NULL, 1),
    (N'ide_field', N'demo_proj.dbo.api_card_fields', N'api_card_fields', N'id', 0, NULL, 200, N'card_id, list_order, name', NULL, 1),
    (N'ide_action', N'demo_proj.dbo.api_card_actions', N'api_card_actions', N'id', 0, NULL, 200, N'card_id, action_order, name', N'admin', 1);

SELECT @ide = id FROM dbo.api_card WHERE name = N'ide';
SELECT @ide_field = id FROM dbo.api_card WHERE name = N'ide_field';
SELECT @ide_action = id FROM dbo.api_card WHERE name = N'ide_action';

INSERT INTO dbo.api_card_fields (
    card_id, name, display_name, list_order, detail_order, data_type, [sql]
)
VALUES
    (@ide, N'id', N'ID', 2, 0, N'int', NULL),
    (@ide, N'name', N'Name', 4, 4, N'nvarchar(128)', NULL),
    (@ide, N'tablename', N'Table', 6, 6, N'nvarchar(256)', NULL),
    (@ide, N'basetable', N'Base table', 8, 8, N'nvarchar(256)', NULL),
    (@ide, N'id_column', N'Id column', 10, 10, N'nvarchar(128)', NULL),
    (@ide, N'in_main_menu', N'In menu', 12, 12, N'bit', NULL),
    (@ide, N'menu_keycode', N'Key', 14, 14, N'nvarchar(64)', NULL),
    (@ide, N'record_limit', N'Limit', 16, 16, N'int', NULL),
    (@ide, N'sorting_order', N'Sort', 18, 18, N'nvarchar(512)', NULL),
    (@ide, N'reducer', N'Reducer', 0, 20, N'nvarchar(max)', NULL),
    (@ide, N'error', N'Error', 22, 0, N'nvarchar(max)', NULL);

INSERT INTO dbo.api_card_fields (
    card_id, name, display_name, list_order, detail_order, data_type, [sql]
)
VALUES
    (@ide_field, N'id', N'ID', 2, 0, N'int', NULL),
    (@ide_field, N'card_name', N'Card', 4, 4, N'nvarchar(max)', @card_name_sql),
    (@ide_field, N'card_id', N'Card id', 6, 6, N'int', NULL),
    (@ide_field, N'name', N'Name', 8, 8, N'nvarchar(128)', NULL),
    (@ide_field, N'display_name', N'Label', 10, 10, N'nvarchar(256)', NULL),
    (@ide_field, N'list_order', N'List order', 12, 12, N'int', NULL),
    (@ide_field, N'detail_order', N'Detail order', 14, 14, N'int', NULL),
    (@ide_field, N'list_class', N'Class', 16, 16, N'nvarchar(256)', NULL),
    (@ide_field, N'data_type', N'Type', 18, 18, N'nvarchar(128)', NULL),
    (@ide_field, N'sql', N'SQL', 0, 20, N'nvarchar(max)', NULL);

INSERT INTO dbo.api_card_fields (
    card_id, name, display_name, list_order, detail_order, data_type, [sql]
)
VALUES
    (@ide_action, N'id', N'ID', 2, 0, N'int', NULL),
    (@ide_action, N'card_name', N'Card', 4, 4, N'nvarchar(max)', @card_name_sql),
    (@ide_action, N'card_id', N'Card id', 6, 6, N'int', NULL),
    (@ide_action, N'name', N'Name', 8, 8, N'nvarchar(128)', NULL),
    (@ide_action, N'display_name', N'Label', 10, 10, N'nvarchar(256)', NULL),
    (@ide_action, N'action', N'Kind', 12, 12, N'nvarchar(64)', NULL),
    (@ide_action, N'sql', N'SQL', 0, 14, N'nvarchar(max)', NULL),
    (@ide_action, N'keycode', N'Key', 16, 16, N'nvarchar(64)', NULL),
    (@ide_action, N'type', N'Type', 18, 18, N'nvarchar(32)', NULL),
    (@ide_action, N'action_order', N'Order', 20, 20, N'int', NULL),
    (@ide_action, N'params', N'Params', 0, 22, N'nvarchar(max)', NULL);

INSERT INTO dbo.api_card_actions (
    card_id, name, display_name, action, params, type, action_order, keycode
)
VALUES
    (@ide, N'fields', N'Fields', N'pathname', N'{"pathname":"/ide_field"}', N'list_form', 10, N'F'),
    (@ide, N'actions', N'Actions', N'pathname', N'{"pathname":"/ide_action"}', N'list_form', 20, N'A'),
    (@ide_field, N'cards', N'Cards', N'pathname', N'{"pathname":"/ide"}', N'list_form', 10, NULL),
    (@ide_action, N'cards', N'Cards', N'pathname', N'{"pathname":"/ide"}', N'list_form', 10, NULL);

SET @toast = 0;
EXEC dbo.sp_api_card_create_cache @card_id = @ide, @toast = @toast;
EXEC dbo.sp_api_card_create_cache @card_id = @ide_field, @toast = @toast;
EXEC dbo.sp_api_card_create_cache @card_id = @ide_action, @toast = @toast;
GO
