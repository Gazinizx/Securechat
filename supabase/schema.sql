-- SecureChat schema v2. Run in the Supabase SQL Editor.
create extension if not exists pgcrypto;
create schema if not exists private;
grant usage on schema private to authenticated;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (char_length(username) between 3 and 32),
  created_at timestamptz not null default now()
);
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  ghost_mode boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
create table if not exists public.encrypted_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  ciphertext text not null,
  nonce text not null,
  key_version integer not null default 1,
  read_at timestamptz,
  delete_after_read boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_securechat_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare clean_username text;
begin
  clean_username := lower(trim(coalesce(new.raw_user_meta_data->>'username','')));
  if clean_username !~ '^[a-z0-9_]{3,32}$' then
    clean_username := 'user_' || replace(new.id::text,'-','');
  end if;
  insert into public.profiles(id,username) values(new.id,clean_username)
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_securechat_auth_user_created on auth.users;
create trigger on_securechat_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_securechat_user();

alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.encrypted_messages enable row level security;

-- SECURITY DEFINER avoids recursive RLS checks when determining conversation membership.
create or replace function private.is_conversation_member(p_conversation_id uuid)
returns boolean language sql stable security definer set search_path = public
as $
  select exists (
    select 1 from public.conversation_members m
    where m.conversation_id = p_conversation_id and m.user_id = auth.uid()
  );
$;
revoke all on function private.is_conversation_member(uuid) from public, anon;
grant execute on function private.is_conversation_member(uuid) to authenticated;

drop policy if exists "Authenticated users can read profiles" on public.profiles;
create policy "Authenticated users can read profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "Users can create own profile" on public.profiles;
create policy "Users can create own profile" on public.profiles for insert to authenticated with check (auth.uid() = id);
drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
drop policy if exists "Members can view their conversations" on public.conversations;
drop policy if exists "Members can view conversations" on public.conversations;
create policy "Members can view conversations" on public.conversations for select to authenticated using (private.is_conversation_member(id));
drop policy if exists "Members can view membership rows" on public.conversation_members;
drop policy if exists "Users can view own memberships" on public.conversation_members;
drop policy if exists "Members can view conversation memberships" on public.conversation_members;
create policy "Members can view conversation memberships" on public.conversation_members for select to authenticated using (private.is_conversation_member(conversation_id));
drop policy if exists "Members can read conversation messages" on public.encrypted_messages;
drop policy if exists "Members can read ciphertext" on public.encrypted_messages;
create policy "Members can read ciphertext" on public.encrypted_messages for select to authenticated using (private.is_conversation_member(conversation_id));
drop policy if exists "Conversation members can send messages as themselves" on public.encrypted_messages;
drop policy if exists "Members can insert ciphertext as self" on public.encrypted_messages;
create policy "Members can insert ciphertext as self" on public.encrypted_messages for insert to authenticated with check (sender_id = auth.uid() and private.is_conversation_member(conversation_id));

create or replace function public.create_conversation_with_username(p_username text, p_ghost_mode boolean default false)
returns uuid language plpgsql security definer set search_path = public
as $$
declare target_id uuid; new_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select id into target_id from public.profiles where username = lower(trim(p_username));
  if target_id is null then raise exception 'Username not found'; end if;
  if target_id = auth.uid() then raise exception 'Cannot create a conversation with yourself'; end if;
  -- Reuse an existing one-to-one conversation with the same mode instead of creating duplicates.
  select c.id into new_id
  from public.conversations c
  join public.conversation_members mine on mine.conversation_id = c.id and mine.user_id = auth.uid()
  join public.conversation_members theirs on theirs.conversation_id = c.id and theirs.user_id = target_id
  where c.ghost_mode = coalesce(p_ghost_mode,false)
    and (select count(*) from public.conversation_members cm where cm.conversation_id = c.id) = 2
  order by c.created_at desc
  limit 1;
  if new_id is not null then return new_id; end if;
  insert into public.conversations(created_by, ghost_mode) values(auth.uid(), coalesce(p_ghost_mode,false)) returning id into new_id;
  insert into public.conversation_members(conversation_id,user_id) values(new_id,auth.uid()),(new_id,target_id);
  return new_id;
end;
$$;

create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not exists(select 1 from public.conversation_members where conversation_id=p_conversation_id and user_id=auth.uid()) then raise exception 'Not a conversation member'; end if;
  update public.encrypted_messages set read_at=coalesce(read_at,now())
    where conversation_id=p_conversation_id and sender_id<>auth.uid() and read_at is null;
end;
$$;

create or replace function public.cleanup_ghost_messages(p_conversation_id uuid)
returns integer language plpgsql security definer set search_path = public
as $$
declare deleted_count integer;
begin
  if not exists(select 1 from public.conversation_members where conversation_id=p_conversation_id and user_id=auth.uid()) then raise exception 'Not a conversation member'; end if;
  if not exists(select 1 from public.conversations where id=p_conversation_id and ghost_mode=true) then return 0; end if;
  delete from public.encrypted_messages where conversation_id=p_conversation_id and delete_after_read=true and read_at is not null;
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;
revoke all on function public.create_conversation_with_username(text,boolean) from public;
revoke all on function public.mark_conversation_read(uuid) from public;
revoke all on function public.cleanup_ghost_messages(uuid) from public;
grant execute on function public.create_conversation_with_username(text,boolean) to authenticated;
grant execute on function public.mark_conversation_read(uuid) to authenticated;
grant execute on function public.cleanup_ghost_messages(uuid) to authenticated;

-- E2EE currently relies on a shared passphrase, not audited identity/key exchange or forward secrecy.


-- WebRTC call signaling. Media flows peer-to-peer; this table carries SDP/ICE setup data.
create table if not exists public.call_signals (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  signal_type text not null check (signal_type in ('offer','answer','ice','end','reject')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists call_signals_conversation_created_idx on public.call_signals(conversation_id, created_at);
alter table public.call_signals enable row level security;
drop policy if exists "Conversation members can read call signals" on public.call_signals;
create policy "Conversation members can read call signals" on public.call_signals for select to authenticated
using (private.is_conversation_member(conversation_id) and (sender_id = auth.uid() or receiver_id = auth.uid()));
drop policy if exists "Members can send call signals to conversation partner" on public.call_signals;
create policy "Members can send call signals to conversation partner" on public.call_signals for insert to authenticated
with check (
  sender_id = auth.uid()
  and private.is_conversation_member(conversation_id)
  and exists (select 1 from public.conversation_members m where m.conversation_id = call_signals.conversation_id and m.user_id = call_signals.receiver_id)
  and receiver_id <> auth.uid()
);
drop policy if exists "Call participants can delete signals" on public.call_signals;
create policy "Call participants can delete signals" on public.call_signals for delete to authenticated
using (private.is_conversation_member(conversation_id) and (sender_id = auth.uid() or receiver_id = auth.uid()));
grant select, insert, delete on public.call_signals to authenticated;


-- Private bucket for locally encrypted photo/video bytes. Object paths start with conversation UUID / uploader UUID.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('securechat-media', 'securechat-media', false, 41943040, array['application/octet-stream'])
on conflict (id) do update set public = false, file_size_limit = 41943040, allowed_mime_types = array['application/octet-stream'];
drop policy if exists "SecureChat members can read encrypted media" on storage.objects;
create policy "SecureChat members can read encrypted media" on storage.objects for select to authenticated
using (bucket_id = 'securechat-media' and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and private.is_conversation_member(split_part(name, '/', 1)::uuid));
drop policy if exists "SecureChat members can upload encrypted media" on storage.objects;
create policy "SecureChat members can upload encrypted media" on storage.objects for insert to authenticated
with check (bucket_id = 'securechat-media' and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and private.is_conversation_member(split_part(name, '/', 1)::uuid) and split_part(name, '/', 2) = auth.uid()::text);
drop policy if exists "SecureChat members can delete encrypted media" on storage.objects;
create policy "SecureChat members can delete encrypted media" on storage.objects for delete to authenticated
using (bucket_id = 'securechat-media' and split_part(name, '/', 1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' and private.is_conversation_member(split_part(name, '/', 1)::uuid));
