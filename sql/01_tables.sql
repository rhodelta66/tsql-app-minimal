USE demo_proj;
GO

CREATE TABLE dbo.api_session (
    id          int IDENTITY(1,1) NOT NULL CONSTRAINT pk_api_session PRIMARY KEY,
    token       nvarchar(64)  NOT NULL CONSTRAINT uq_api_session_token UNIQUE,
    user_name   nvarchar(256) NOT NULL,
    user_id     int           NOT NULL,
    created_at  datetime2     NOT NULL CONSTRAINT df_api_session_created DEFAULT (SYSUTCDATETIME())
);
GO

CREATE TABLE dbo.api_session_storage (
    session_id  int            NOT NULL,
    name        nvarchar(128)  NOT NULL,
    value       nvarchar(max)  NULL,
    CONSTRAINT pk_api_session_storage PRIMARY KEY (session_id, name),
    CONSTRAINT fk_api_session_storage_session FOREIGN KEY (session_id)
        REFERENCES dbo.api_session (id) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.api_modal_post (
    session_id  int            NOT NULL,
    name        nvarchar(128)  NOT NULL,
    value       nvarchar(max)  NULL,
    CONSTRAINT pk_api_modal_post PRIMARY KEY (session_id, name),
    CONSTRAINT fk_api_modal_post_session FOREIGN KEY (session_id)
        REFERENCES dbo.api_session (id) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.api_modal_state (
    session_id       int            NOT NULL CONSTRAINT pk_api_modal_state PRIMARY KEY,
    is_open          bit            NOT NULL CONSTRAINT df_modal_open DEFAULT (0),
    clear_requested  bit            NOT NULL CONSTRAINT df_modal_clear DEFAULT (0),
    action_id        int            NULL,
    css_class        nvarchar(128)  NULL,
    path             nvarchar(400)  NULL,
    CONSTRAINT fk_api_modal_state_session FOREIGN KEY (session_id)
        REFERENCES dbo.api_session (id) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.api_modal_render (
    id          int IDENTITY(1,1) NOT NULL CONSTRAINT pk_api_modal_render PRIMARY KEY,
    session_id  int            NOT NULL,
    seq         int            NOT NULL,
    kind        nvarchar(32)   NOT NULL,
    payload     nvarchar(max)  NOT NULL,
    CONSTRAINT uq_api_modal_render_seq UNIQUE (session_id, seq),
    CONSTRAINT fk_api_modal_render_session FOREIGN KEY (session_id)
        REFERENCES dbo.api_session (id) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.api_toast (
    id          int IDENTITY(1,1) NOT NULL CONSTRAINT pk_api_toast PRIMARY KEY,
    session_id  int            NOT NULL,
    text        nvarchar(max)  NOT NULL,
    css_class   nvarchar(128)  NULL,
    CONSTRAINT fk_api_toast_session FOREIGN KEY (session_id)
        REFERENCES dbo.api_session (id) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.api_card (
    id                    int IDENTITY(1,1) NOT NULL CONSTRAINT pk_api_card PRIMARY KEY,
    name                  nvarchar(128)  NOT NULL CONSTRAINT uq_api_card_name UNIQUE,
    tablename             nvarchar(256)  NULL,
    basetable             nvarchar(256)  NULL,
    id_column             nvarchar(128)  NULL,
    list_select_cache     nvarchar(max)  NULL,
    select_cache          nvarchar(max)  NULL,
    declare_cache         nvarchar(max)  NULL,
    crud_create           nvarchar(max)  NULL,
    crud_read             nvarchar(max)  NULL,
    crud_update           nvarchar(max)  NULL,
    crud_delete           nvarchar(max)  NULL,
    role                  nvarchar(128)  NULL,
    deny_role             nvarchar(128)  NULL,
    ide_role              nvarchar(128)  NULL,
    is_system             bit            NOT NULL CONSTRAINT df_api_card_system DEFAULT (0),
    in_main_menu          bit            NOT NULL CONSTRAINT df_api_card_menu DEFAULT (0),
    menu_keycode          nvarchar(64)   NULL,
    menu_group_id         int            NULL,
    record_limit          int            NULL,
    record_threshold      int            NULL,
    auto_refresh_seconds  int            NULL,
    reducer               nvarchar(max)  NULL,
    sorting_order         nvarchar(512)  NULL,
    error                 nvarchar(max)  NULL,
    header_sql            nvarchar(max)  NULL
);
GO

CREATE TABLE dbo.api_card_fields (
    id                 int IDENTITY(1,1) NOT NULL CONSTRAINT pk_api_card_fields PRIMARY KEY,
    card_id            int            NOT NULL,
    name               nvarchar(128)  NOT NULL,
    display_name       nvarchar(256)  NULL,
    list_order         int            NULL,
    detail_order       int            NULL,
    sql                nvarchar(max)  NULL,
    list_class         nvarchar(256)  NULL,
    seek_order         int            NULL,
    seek_prefix        nvarchar(32)   NULL,
    seek_length        int            NULL,
    picklist_card_id   int            NULL,
    instant_update     bit            NOT NULL CONSTRAINT df_field_instant DEFAULT (0),
    data_type          nvarchar(128)  NULL,
    CONSTRAINT uq_api_card_fields_name UNIQUE (card_id, name),
    CONSTRAINT fk_api_card_fields_card FOREIGN KEY (card_id)
        REFERENCES dbo.api_card (id) ON DELETE CASCADE
);
GO

CREATE TABLE dbo.api_card_actions (
    id             int IDENTITY(1,1) NOT NULL CONSTRAINT pk_api_card_actions PRIMARY KEY,
    card_id        int            NULL,
    name           nvarchar(128)  NOT NULL,
    display_name   nvarchar(256)  NULL,
    action         nvarchar(64)   NOT NULL,
    sql            nvarchar(max)  NULL,
    unparsed_sql   nvarchar(max)  NULL,
    pre_declare    nvarchar(max)  NULL,
    keycode        nvarchar(64)   NULL,
    type           nvarchar(32)   NULL,
    role           nvarchar(128)  NULL,
    deny_role      nvarchar(128)  NULL,
    params         nvarchar(max)  NULL,
    action_order   int            NOT NULL CONSTRAINT df_action_order DEFAULT (10),
    CONSTRAINT fk_api_card_actions_card FOREIGN KEY (card_id)
        REFERENCES dbo.api_card (id) ON DELETE CASCADE
);
GO

-- A related card. parent is the card the user is on. child is the card the
-- menu opens. Two CASCADE foreign keys to api_card are rejected, so only
-- parent cascades. Bound rows filter child.ref. Unbound rows use reducer.
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
GO
