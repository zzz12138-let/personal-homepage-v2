-- 个人主页在线留言：表结构 + 行级安全 + 只允许改 is_read 的触发器
-- 在 Supabase SQL Editor 里整体执行即可（可重复执行）。
-- 注意：管理员邮箱 3372794468@qq.com 出现两处，换邮箱时要与 assets/config.js 同步。

create extension if not exists pgcrypto;

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  nickname text not null default '',
  message text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  client_hash text not null,
  constraint feedback_nickname_length check (char_length(nickname) <= 50),
  constraint feedback_message_length check (char_length(message) between 10 and 2000),
  constraint feedback_client_hash_length check (char_length(client_hash) = 64)
);

create index if not exists feedback_created_at_idx on public.feedback (created_at desc);
create index if not exists feedback_unread_idx on public.feedback (is_read, created_at desc);
create index if not exists feedback_client_rate_idx on public.feedback (client_hash, created_at desc);

alter table public.feedback enable row level security;
revoke all on public.feedback from anon;
revoke all on public.feedback from authenticated;
grant select, update on public.feedback to authenticated;

create policy "admin can read feedback"
on public.feedback for select
to authenticated
using ((auth.jwt() ->> 'email') = '3372794468@qq.com');

create policy "admin can update read state"
on public.feedback for update
to authenticated
using ((auth.jwt() ->> 'email') = '3372794468@qq.com')
with check ((auth.jwt() ->> 'email') = '3372794468@qq.com');

create or replace function public.protect_feedback_fields()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  if new.id <> old.id
    or new.nickname <> old.nickname
    or new.message <> old.message
    or new.created_at <> old.created_at
    or new.client_hash <> old.client_hash then
    raise exception 'only is_read may be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists feedback_only_read_state on public.feedback;
create trigger feedback_only_read_state
before update on public.feedback
for each row execute function public.protect_feedback_fields();
