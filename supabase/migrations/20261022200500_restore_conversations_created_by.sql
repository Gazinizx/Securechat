-- Restore the creator column expected by create_conversation_with_username().
-- The live database had drifted from supabase/schema.sql, causing PostgreSQL 42703.
alter table public.conversations
  add column if not exists created_by uuid references auth.users(id) on delete cascade;

-- Preserve existing conversations if any were created before this repair.
update public.conversations c
set created_by = (
  select cm.user_id
  from public.conversation_members cm
  where cm.conversation_id = c.id
  order by cm.joined_at asc, cm.user_id asc
  limit 1
)
where c.created_by is null;

-- A conversation must always have a creator. Any legacy orphan would fail here
-- instead of silently assigning a made-up owner.
alter table public.conversations alter column created_by set not null;
