-- SecureChat starter schema. Review before applying to a Supabase project.
-- Store only client-encrypted ciphertext; never store plaintext message bodies.
create extension if not exists pgcrypto;

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
  user_id uuid not null references auth.users(id) on delete cascade,
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
alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.encrypted_messages enable row level security;

create policy "Authenticated users can read profiles" on public.profiles
 for select to authenticated using (true);
create policy "Users can create own profile" on public.profiles
 for insert to authenticated with check (auth.uid() = id);
create policy "Users can update own profile" on public.profiles
 for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
create policy "Members can view conversations" on public.conversations
 for select to authenticated using (
   exists(select 1 from public.conversation_members m where m.conversation_id = conversations.id and m.user_id = auth.uid())
 );
create policy "Users can view own memberships" on public.conversation_members
 for select to authenticated using (user_id = auth.uid());
create policy "Members can read ciphertext" on public.encrypted_messages
 for select to authenticated using (
   exists(select 1 from public.conversation_members m where m.conversation_id = encrypted_messages.conversation_id and m.user_id = auth.uid())
 );
create policy "Members can insert ciphertext as self" on public.encrypted_messages
 for insert to authenticated with check (
   sender_id = auth.uid() and exists(
     select 1 from public.conversation_members m where m.conversation_id = encrypted_messages.conversation_id and m.user_id = auth.uid()
   )
 );
-- Intentionally no client-side update/delete policy yet. Membership creation,
-- read receipts, and idempotent ghost deletion require reviewed server functions.
