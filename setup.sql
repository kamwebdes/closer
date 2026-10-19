-- Closer database setup. Paste all of this into Supabase > SQL Editor and click Run.
-- Safe to run more than once.

-- 1. Each contractor's estimates, saved as one backup per account.
create table if not exists public.closer_data (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.closer_data enable row level security;

drop policy if exists "closer_data own select" on public.closer_data;
drop policy if exists "closer_data own insert" on public.closer_data;
drop policy if exists "closer_data own update" on public.closer_data;
drop policy if exists "closer_data own delete" on public.closer_data;
create policy "closer_data own select" on public.closer_data for select to authenticated using ((select auth.uid()) = user_id);
create policy "closer_data own insert" on public.closer_data for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "closer_data own update" on public.closer_data for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "closer_data own delete" on public.closer_data for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.closer_data from anon;
grant select, insert, update, delete on public.closer_data to authenticated;

-- 2. Estimates shared with customers through an approval link.
create table if not exists public.shared_estimates (
  token         text primary key check (length(token) >= 20),
  user_id       uuid not null references auth.users(id) on delete cascade,
  quote_id      text not null,
  doc           jsonb not null,
  status        text not null default 'open' check (status in ('open','approved','declined')),
  customer_name text check (customer_name is null or length(customer_name) <= 80),
  responded_at  timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists shared_estimates_user_idx on public.shared_estimates(user_id);
alter table public.shared_estimates enable row level security;

drop policy if exists "shared own select" on public.shared_estimates;
drop policy if exists "shared own insert" on public.shared_estimates;
drop policy if exists "shared own update" on public.shared_estimates;
drop policy if exists "shared own delete" on public.shared_estimates;
create policy "shared own select" on public.shared_estimates for select to authenticated using ((select auth.uid()) = user_id);
create policy "shared own insert" on public.shared_estimates for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "shared own update" on public.shared_estimates for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "shared own delete" on public.shared_estimates for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on public.shared_estimates from anon;
grant select, insert, update, delete on public.shared_estimates to authenticated;

-- 3. Customers (not signed in) can only open ONE estimate, and only if they have its secret link.
create or replace function public.get_shared_estimate(p_token text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'doc', doc, 'status', status,
    'customer_name', customer_name, 'responded_at', responded_at)
  from public.shared_estimates
  where token = p_token;
$$;

create or replace function public.respond_shared_estimate(p_token text, p_name text, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r public.shared_estimates;
begin
  if p_status not in ('approved','declined') then
    raise exception 'Choose approve or decline.';
  end if;
  if length(coalesce(trim(p_name), '')) < 2 or length(p_name) > 80 then
    raise exception 'Type your full name.';
  end if;
  update public.shared_estimates
     set status = p_status, customer_name = trim(p_name), responded_at = now()
   where token = p_token and status = 'open'
  returning * into r;
  if not found then
    raise exception 'This estimate is not open.';
  end if;
  return jsonb_build_object('status', r.status);
end;
$$;

revoke all on function public.get_shared_estimate(text) from public;
revoke all on function public.respond_shared_estimate(text, text, text) from public;
grant execute on function public.get_shared_estimate(text) to anon, authenticated;
grant execute on function public.respond_shared_estimate(text, text, text) to anon, authenticated;

-- 4. Let people delete their own account and everything in it (Apple requires this).
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first.';
  end if;
  delete from public.shared_estimates where user_id = auth.uid();
  delete from public.closer_data where user_id = auth.uid();
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- 5. Messages from the support page. Read them in Table Editor > support_messages.
create table if not exists public.support_messages (
  id         bigint generated always as identity primary key,
  name       text check (name is null or length(name) <= 80),
  email      text not null check (length(email) between 5 and 200),
  message    text not null check (length(message) between 5 and 4000),
  created_at timestamptz not null default now()
);
alter table public.support_messages enable row level security;
revoke all on public.support_messages from anon, authenticated;

create or replace function public.submit_support(p_name text, p_email text, p_message text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_email is null or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(p_email) > 200 then
    raise exception 'Enter a valid email address.';
  end if;
  if length(coalesce(trim(p_message), '')) < 5 or length(p_message) > 4000 then
    raise exception 'Write a message of at least a few words.';
  end if;
  if (select count(*) from public.support_messages
      where email = lower(trim(p_email)) and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'You''ve sent several messages already. Please wait a bit before sending another.';
  end if;
  insert into public.support_messages(name, email, message)
  values (nullif(left(trim(coalesce(p_name, '')), 80), ''), lower(trim(p_email)), trim(p_message));
end;
$$;
revoke all on function public.submit_support(text, text, text) from public;
grant execute on function public.submit_support(text, text, text) to anon, authenticated;
