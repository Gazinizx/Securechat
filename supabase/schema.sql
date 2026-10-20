-- SecureChat MVP schema
-- Run in Supabase SQL Editor. Never disable RLS.
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  room_id text not null,
  sender_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  ciphertext text not null,
  iv text not null,
  created_at timestamptz not null default now()
);

alter table public.chat_messages enable row level security;

revoke all on public.chat_messages from anon;
grant select, insert on public.chat_messages to authenticated;

drop policy if exists "authenticated users can read room ciphertext" on public.chat_messages;
create policy "authenticated users can read room ciphertext"
  on public.chat_messages for select
  to authenticated
  using (true);

drop policy if exists "authenticated users can insert own ciphertext" on public.chat_messages;
create policy "authenticated users can insert own ciphertext"
  on public.chat_messages for insert
  to authenticated
  with check (auth.uid() = sender_id);

create index if not exists chat_messages_room_created_idx
  on public.chat_messages (room_id, created_at desc);

alter publication supabase_realtime add table public.chat_messages;
