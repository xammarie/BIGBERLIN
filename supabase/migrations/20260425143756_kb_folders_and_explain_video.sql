-- Add KB folders + new action 'explain_video' + chat folder selection.

-- 1) Add 'explain_video' to the action enum (Postgres requires this in its own statement
--    and committed before we can use it; for hackathon we just add it.)
alter type session_action add value if not exists 'explain_video';

-- 2) New table: knowledge_base_folders
create table knowledge_base_folders (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    is_default boolean not null default false,
    created_at timestamptz not null default now()
);
create index knowledge_base_folders_user_idx on knowledge_base_folders (user_id);
create unique index knowledge_base_folders_one_default_per_user
    on knowledge_base_folders (user_id)
    where is_default = true;

alter table knowledge_base_folders enable row level security;
create policy "own kb folders" on knowledge_base_folders
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- 3) Add folder_id to knowledge_base_items
alter table knowledge_base_items
    add column folder_id uuid references knowledge_base_folders(id) on delete set null;
create index knowledge_base_items_folder_idx on knowledge_base_items (folder_id);

-- 4) Add knowledge_base_folder_id + title to chats
--    folder_id null  = no folder context (or 'all' depending on UI)
alter table chats
    add column knowledge_base_folder_id uuid references knowledge_base_folders(id) on delete set null,
    add column title text;
