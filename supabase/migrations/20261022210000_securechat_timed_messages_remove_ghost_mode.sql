alter table public.conversations add column if not exists message_expiry_seconds integer not null default 0;
alter table public.encrypted_messages add column if not exists expires_at timestamptz;
alter table public.conversations drop constraint if exists conversations_message_expiry_seconds_check;
alter table public.conversations add constraint conversations_message_expiry_seconds_check check (message_expiry_seconds in (0, 7200, 21600, 43200, 86400, 604800));
create index if not exists encrypted_messages_expires_at_idx on public.encrypted_messages (expires_at) where expires_at is not null;
drop policy if exists "Conversation members can update message expiry" on public.conversations;
create policy "Conversation members can update message expiry" on public.conversations for update to authenticated using (private.is_conversation_member(id)) with check (private.is_conversation_member(id));
create or replace function public.set_message_expiry() returns trigger language plpgsql security invoker set search_path = public as $$
declare expiry_seconds integer;
begin
 select c.message_expiry_seconds into expiry_seconds from public.conversations c where c.id = new.conversation_id;
 if coalesce(expiry_seconds, 0) > 0 then new.expires_at := now() + make_interval(secs => expiry_seconds); else new.expires_at := null; end if;
 return new;
end; $$;
drop trigger if exists set_encrypted_message_expiry on public.encrypted_messages;
create trigger set_encrypted_message_expiry before insert on public.encrypted_messages for each row execute function public.set_message_expiry();
create or replace function public.delete_expired_messages() returns integer language plpgsql security definer set search_path = public as $$
declare deleted_count integer;
begin
 delete from public.encrypted_messages where expires_at is not null and expires_at <= now();
 get diagnostics deleted_count = row_count;
 return deleted_count;
end; $$;
revoke all on function public.delete_expired_messages() from public, anon, authenticated;
create extension if not exists pg_cron;
do $$ begin
 if exists (select 1 from cron.job where jobname = 'securechat-delete-expired-messages') then perform cron.unschedule('securechat-delete-expired-messages'); end if;
 perform cron.schedule('securechat-delete-expired-messages', '* * * * *', 'select public.delete_expired_messages();');
end; $$;
drop function if exists public.create_conversation_with_username(text, boolean);
drop function if exists public.create_conversation_with_username(text);
create function public.create_conversation_with_username(p_username text) returns uuid language plpgsql security definer set search_path = public as $$
declare target_id uuid; new_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select id into target_id from public.profiles where username = lower(trim(p_username));
 if target_id is null then raise exception 'Username not found'; end if;
 if target_id = auth.uid() then raise exception 'Cannot create a conversation with yourself'; end if;
 select c.id into new_id from public.conversations c
 join public.conversation_members mine on mine.conversation_id = c.id and mine.user_id = auth.uid()
 join public.conversation_members theirs on theirs.conversation_id = c.id and theirs.user_id = target_id
 where (select count(*) from public.conversation_members cm where cm.conversation_id = c.id) = 2
 order by c.created_at desc limit 1;
 if new_id is not null then return new_id; end if;
 insert into public.conversations(created_by, message_expiry_seconds) values(auth.uid(), 0) returning id into new_id;
 insert into public.conversation_members(conversation_id,user_id) values(new_id,auth.uid()),(new_id,target_id);
 return new_id;
end; $$;
revoke all on function public.create_conversation_with_username(text) from public;
grant execute on function public.create_conversation_with_username(text) to authenticated;

create table if not exists public.user_encryption_keys (
  user_id uuid primary key references auth.users(id) on delete cascade,
  public_key text not null,
  updated_at timestamptz not null default now()
);
alter table public.user_encryption_keys enable row level security;
drop policy if exists "Authenticated users can read public encryption keys" on public.user_encryption_keys;
create policy "Authenticated users can read public encryption keys" on public.user_encryption_keys for select to authenticated using (true);
drop policy if exists "Users can publish own encryption key" on public.user_encryption_keys;
create policy "Users can publish own encryption key" on public.user_encryption_keys for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Users can update own encryption key" on public.user_encryption_keys;
create policy "Users can update own encryption key" on public.user_encryption_keys for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.user_encryption_keys to authenticated;
revoke update on public.conversations from authenticated;
grant update (message_expiry_seconds) on public.conversations to authenticated;
