-- BIGBERLINHACK 2026 — initial schema
-- homework copilot: handwriting library, knowledge base, action sessions, chats

-- =====================================================
-- enums
-- =====================================================

create type session_action as enum (
    'correct',
    'complete',
    'fill_out',
    'annotate',
    'schrift_replace'
);

create type session_status as enum (
    'pending',
    'processing',
    'complete',
    'failed'
);

create type handwriting_mode as enum (
    'library',
    'adaptive'
);

-- =====================================================
-- handwriting samples (per-user library)
-- =====================================================

create table handwriting_samples (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    name text not null,
    storage_path text not null,
    is_default boolean not null default false,
    created_at timestamptz not null default now()
);
create index handwriting_samples_user_idx on handwriting_samples (user_id);
create unique index handwriting_samples_one_default_per_user
    on handwriting_samples (user_id)
    where is_default = true;

-- =====================================================
-- knowledge base (optional onboarding context)
-- =====================================================

create table knowledge_base_items (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    storage_path text not null,
    filename text not null,
    mime_type text,
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);
create index knowledge_base_items_user_idx on knowledge_base_items (user_id);

-- =====================================================
-- sessions (one per action)
-- =====================================================

create table sessions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    action session_action not null,
    status session_status not null default 'pending',
    handwriting_sample_id uuid references handwriting_samples(id) on delete set null,
    mode handwriting_mode not null default 'library',
    error text,
    created_at timestamptz not null default now(),
    completed_at timestamptz
);
create index sessions_user_created_idx on sessions (user_id, created_at desc);

-- =====================================================
-- session inputs (uploaded images)
-- =====================================================

create table session_inputs (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references sessions(id) on delete cascade,
    storage_path text not null,
    "order" int not null default 0,
    created_at timestamptz not null default now()
);
create index session_inputs_session_idx on session_inputs (session_id);

-- =====================================================
-- session outputs (gpt-image-2 results)
-- =====================================================

create table session_outputs (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references sessions(id) on delete cascade,
    source_input_id uuid references session_inputs(id) on delete cascade,
    storage_path text not null,
    prompt_used text,
    created_at timestamptz not null default now()
);
create index session_outputs_session_idx on session_outputs (session_id);

-- =====================================================
-- chats (voice + text conversations)
-- =====================================================

create table chats (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    session_id uuid references sessions(id) on delete set null,
    messages jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index chats_user_updated_idx on chats (user_id, updated_at desc);

create or replace function set_updated_at()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

create trigger chats_updated_at
    before update on chats
    for each row execute function set_updated_at();

-- =====================================================
-- row level security
-- =====================================================

alter table handwriting_samples   enable row level security;
alter table knowledge_base_items  enable row level security;
alter table sessions              enable row level security;
alter table session_inputs        enable row level security;
alter table session_outputs       enable row level security;
alter table chats                 enable row level security;

create policy "own handwriting" on handwriting_samples
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

create policy "own kb" on knowledge_base_items
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

create policy "own sessions" on sessions
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

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
        exists (
            select 1 from sessions
            where sessions.id = session_inputs.session_id
              and sessions.user_id = auth.uid()
        )
    );

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
        exists (
            select 1 from sessions
            where sessions.id = session_outputs.session_id
              and sessions.user_id = auth.uid()
        )
    );

create policy "own chats" on chats
    for all
    using (user_id = auth.uid())
    with check (user_id = auth.uid());

-- =====================================================
-- storage buckets + policies
-- =====================================================

insert into storage.buckets (id, name, public)
values
    ('handwriting',       'handwriting',       false),
    ('worksheets-input',  'worksheets-input',  false),
    ('worksheets-output', 'worksheets-output', false),
    ('kb-files',          'kb-files',          false)
on conflict (id) do nothing;

create policy "own handwriting files" on storage.objects
    for all
    using (
        bucket_id = 'handwriting'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'handwriting'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "own worksheet inputs" on storage.objects
    for all
    using (
        bucket_id = 'worksheets-input'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'worksheets-input'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "own worksheet outputs" on storage.objects
    for all
    using (
        bucket_id = 'worksheets-output'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'worksheets-output'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "own kb files" on storage.objects
    for all
    using (
        bucket_id = 'kb-files'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'kb-files'
        and (storage.foldername(name))[1] = auth.uid()::text
    );
