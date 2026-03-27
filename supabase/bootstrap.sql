-- Daily Quest: Supabase bootstrap
-- Run this in Supabase SQL Editor for a fresh project.

create extension if not exists pgcrypto;

-- Core profile table linked to auth.users
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  display_name text,
  email text not null unique,
  enable_custom_quest boolean not null default false,
  image_url text,
  provider text not null default 'email',
  quest_counts integer not null default 0
);

create table if not exists public.quests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete cascade,
  emoji text not null,
  public boolean not null default false,
  title text not null
);

create table if not exists public.quest_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  log_date timestamptz not null default now(),
  is_completed boolean not null default false,
  count integer not null default 0,
  quest_counts integer not null default 0
);

create table if not exists public.strike (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  count integer not null default 0
);

create table if not exists public.challenger (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  reviewer_id uuid not null unique references public.profiles(id) on delete cascade,
  is_accepted boolean default false,
  created_at timestamptz not null default now(),
  constraint challenger_no_self check (user_id <> reviewer_id)
);

create table if not exists public.notification (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  notification_json text not null,
  created_at timestamptz not null default now()
);

-- Optional helper table to match generated types
create table if not exists public.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text not null,
  name text not null,
  owner_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (bucket_id, name)
);

create table if not exists public.quest_progress (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  image_url text not null,
  is_completed boolean not null default false,
  object_id uuid,
  quest_id uuid not null references public.quests(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade
);

alter table public.quest_progress
  drop constraint if exists quest_progress_object_id_fkey;

alter table public.quest_progress
  add constraint quest_progress_object_id_fkey
  foreign key (object_id) references public.objects(id) on delete set null;

create index if not exists idx_quests_created_by on public.quests(created_by);
create index if not exists idx_quest_log_user_date on public.quest_log(user_id, log_date);
create index if not exists idx_quest_progress_user on public.quest_progress(user_id);
create index if not exists idx_quest_progress_quest on public.quest_progress(quest_id);

-- Auto-create profile + strike row after first auth signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name, image_url, provider)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data->>'name', split_part(coalesce(new.email, ''), '@', 1)),
    new.raw_user_meta_data->>'avatar_url',
    coalesce(new.app_metadata->>'provider', 'email')
  )
  on conflict (id) do update
  set
    email = excluded.email,
    display_name = coalesce(public.profiles.display_name, excluded.display_name),
    image_url = coalesce(public.profiles.image_url, excluded.image_url);

  insert into public.strike (user_id, count)
  values (new.id, 0)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- RLS
alter table public.profiles enable row level security;
alter table public.quests enable row level security;
alter table public.quest_log enable row level security;
alter table public.strike enable row level security;
alter table public.challenger enable row level security;
alter table public.notification enable row level security;
alter table public.objects enable row level security;
alter table public.quest_progress enable row level security;

-- Profiles
create policy if not exists profiles_select_self on public.profiles
for select using (auth.uid() = id);

create policy if not exists profiles_insert_self on public.profiles
for insert with check (auth.uid() = id);

create policy if not exists profiles_update_self on public.profiles
for update using (auth.uid() = id) with check (auth.uid() = id);

-- Quests (owner + public read)
create policy if not exists quests_select_owner_or_public on public.quests
for select using (public = true or created_by = auth.uid());

create policy if not exists quests_insert_owner on public.quests
for insert with check (created_by = auth.uid());

create policy if not exists quests_update_owner on public.quests
for update using (created_by = auth.uid()) with check (created_by = auth.uid());

create policy if not exists quests_delete_owner on public.quests
for delete using (created_by = auth.uid());

-- Quest log
create policy if not exists quest_log_select_self on public.quest_log
for select using (user_id = auth.uid());

create policy if not exists quest_log_insert_self on public.quest_log
for insert with check (user_id = auth.uid());

create policy if not exists quest_log_update_self on public.quest_log
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy if not exists quest_log_delete_self on public.quest_log
for delete using (user_id = auth.uid());

-- Strike
create policy if not exists strike_select_self on public.strike
for select using (user_id = auth.uid());

create policy if not exists strike_insert_self on public.strike
for insert with check (user_id = auth.uid());

create policy if not exists strike_update_self on public.strike
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Challenger (both sides can read/manage)
create policy if not exists challenger_select_participant on public.challenger
for select using (user_id = auth.uid() or reviewer_id = auth.uid());

create policy if not exists challenger_insert_user on public.challenger
for insert with check (user_id = auth.uid());

create policy if not exists challenger_update_participant on public.challenger
for update using (user_id = auth.uid() or reviewer_id = auth.uid())
with check (user_id = auth.uid() or reviewer_id = auth.uid());

create policy if not exists challenger_delete_participant on public.challenger
for delete using (user_id = auth.uid() or reviewer_id = auth.uid());

-- Notification
create policy if not exists notification_select_self on public.notification
for select using (user_id = auth.uid());

create policy if not exists notification_insert_self on public.notification
for insert with check (user_id = auth.uid());

create policy if not exists notification_update_self on public.notification
for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy if not exists notification_delete_self on public.notification
for delete using (user_id = auth.uid());

-- Objects
create policy if not exists objects_select_owner on public.objects
for select using (owner_id = auth.uid());

create policy if not exists objects_insert_owner on public.objects
for insert with check (owner_id = auth.uid());

create policy if not exists objects_update_owner on public.objects
for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy if not exists objects_delete_owner on public.objects
for delete using (owner_id = auth.uid());

-- Quest progress (owner can manage, reviewer can read accepted challenger progress)
create policy if not exists quest_progress_select_owner_or_reviewer on public.quest_progress
for select using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.challenger c
    where c.user_id = public.quest_progress.user_id
      and c.reviewer_id = auth.uid()
      and coalesce(c.is_accepted, false) = true
  )
);

create policy if not exists quest_progress_insert_owner on public.quest_progress
for insert with check (user_id = auth.uid());

create policy if not exists quest_progress_update_owner_or_reviewer on public.quest_progress
for update using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.challenger c
    where c.user_id = public.quest_progress.user_id
      and c.reviewer_id = auth.uid()
      and coalesce(c.is_accepted, false) = true
  )
)
with check (true);

create policy if not exists quest_progress_delete_owner on public.quest_progress
for delete using (user_id = auth.uid());

-- Storage bucket used by this app for quest images
insert into storage.buckets (id, name, public)
values ('images', 'images', true)
on conflict (id) do nothing;

-- Public read policy for image rendering
create policy if not exists images_public_read
on storage.objects
for select
using (bucket_id = 'images');

-- Authenticated users can upload under their user prefix
create policy if not exists images_insert_authenticated
on storage.objects
for insert
with check (
  bucket_id = 'images'
  and auth.role() = 'authenticated'
);
