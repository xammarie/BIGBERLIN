-- Security hardening:
-- - keep user-owned rows from pointing at another user's related rows
-- - require user-prefixed storage paths in client-writable metadata
-- - bind Hera video job status checks to the creating user

-- -----------------------------------------------------
-- Basic shape constraints for client-provided text/paths
-- -----------------------------------------------------

alter table handwriting_samples
    add constraint handwriting_samples_name_len
    check (char_length(btrim(name)) between 1 and 120) not valid,
    add constraint handwriting_samples_storage_path_owned
    check (storage_path like user_id::text || '/%') not valid;

alter table knowledge_base_items
    add constraint knowledge_base_items_filename_len
    check (char_length(btrim(filename)) between 1 and 180) not valid,
    add constraint knowledge_base_items_storage_path_owned
    check (storage_path like user_id::text || '/%') not valid;

alter table knowledge_base_folders
    add constraint knowledge_base_folders_name_len
    check (char_length(btrim(name)) between 1 and 120) not valid;

alter table chats
    add constraint chats_title_len
    check (title is null or char_length(btrim(title)) <= 120) not valid;

-- -----------------------------------------------------
-- Stronger RLS relationship checks
-- -----------------------------------------------------

drop policy if exists "own handwriting" on handwriting_samples;
create policy "own handwriting" on handwriting_samples
    for all
    using (user_id = auth.uid())
    with check (
        user_id = auth.uid()
        and storage_path like auth.uid()::text || '/%'
    );

drop policy if exists "own kb folders" on knowledge_base_folders;
create policy "own kb folders" on knowledge_base_folders
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

drop policy if exists "own kb" on knowledge_base_items;
create policy "own kb" on knowledge_base_items
    for all
    using (user_id = auth.uid())
    with check (
        user_id = auth.uid()
        and storage_path like auth.uid()::text || '/%'
        and (
            folder_id is null
            or exists (
                select 1
                from knowledge_base_folders
                where knowledge_base_folders.id = knowledge_base_items.folder_id
                  and knowledge_base_folders.user_id = auth.uid()
            )
        )
    );

drop policy if exists "own sessions" on sessions;
create policy "own sessions" on sessions
    for all
    using (user_id = auth.uid())
    with check (
        user_id = auth.uid()
        and (
            handwriting_sample_id is null
            or exists (
                select 1
                from handwriting_samples
                where handwriting_samples.id = sessions.handwriting_sample_id
                  and handwriting_samples.user_id = auth.uid()
            )
        )
    );

drop policy if exists "own session inputs" on session_inputs;
create policy "own session inputs" on session_inputs
    for all
    using (
        exists (
            select 1 from sessions
            where sessions.id = session_inputs.session_id
              and sessions.user_id = auth.uid()
        )
    )
    with check (
        storage_path like auth.uid()::text || '/%'
        and exists (
            select 1 from sessions
            where sessions.id = session_inputs.session_id
              and sessions.user_id = auth.uid()
        )
    );

drop policy if exists "own session outputs" on session_outputs;
create policy "own session outputs" on session_outputs
    for all
    using (
        exists (
            select 1 from sessions
            where sessions.id = session_outputs.session_id
              and sessions.user_id = auth.uid()
        )
    )
    with check (
        storage_path like auth.uid()::text || '/%'
        and exists (
            select 1 from sessions
            where sessions.id = session_outputs.session_id
              and sessions.user_id = auth.uid()
        )
    );

drop policy if exists "own chats" on chats;
create policy "own chats" on chats
    for all
    using (user_id = auth.uid())
    with check (
        user_id = auth.uid()
        and (
            session_id is null
            or exists (
                select 1
                from sessions
                where sessions.id = chats.session_id
                  and sessions.user_id = auth.uid()
            )
        )
        and (
            knowledge_base_folder_id is null
            or exists (
                select 1
                from knowledge_base_folders
                where knowledge_base_folders.id = chats.knowledge_base_folder_id
                  and knowledge_base_folders.user_id = auth.uid()
            )
        )
    );

-- -----------------------------------------------------
-- User-bound video job registry for secure status checks
-- -----------------------------------------------------

create table video_jobs (
    job_id text primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    prompt text not null,
    status text not null default 'queued',
    video_url text,
    error text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index video_jobs_user_created_idx on video_jobs (user_id, created_at desc);

create trigger video_jobs_updated_at
    before update on video_jobs
    for each row execute function set_updated_at();

alter table video_jobs enable row level security;

create policy "own video jobs" on video_jobs
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());
