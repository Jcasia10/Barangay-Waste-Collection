-- Run this in the Supabase SQL editor.
-- It enables RLS and creates admin-only policies based on public.users.role = 'admin'.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

alter table public.barangay enable row level security;
alter table public.collection_logs enable row level security;
alter table public.collection_schedules enable row level security;
alter table public.users enable row level security;
alter table public.waste_reports enable row level security;

-- Remove existing policies first so this script can be rerun safely.
drop policy if exists "Admins can read barangays" on public.barangay;
drop policy if exists "Admins can read collection logs" on public.collection_logs;
drop policy if exists "Admins can update collection logs" on public.collection_logs;
drop policy if exists "Admins can read collection schedules" on public.collection_schedules;
drop policy if exists "Admins can update collection schedules" on public.collection_schedules;
drop policy if exists "Admins can insert collection schedules" on public.collection_schedules;
drop policy if exists "Admins can delete collection schedules" on public.collection_schedules;
drop policy if exists "Admins can read users" on public.users;
drop policy if exists "Admins can update users" on public.users;
drop policy if exists "Users can insert own profile" on public.users;
drop policy if exists "Users can read own profile" on public.users;
drop policy if exists "Users can update own profile" on public.users;
drop policy if exists "Admins can read waste reports" on public.waste_reports;
drop policy if exists "Admins can update waste reports" on public.waste_reports;

create policy "Admins can read barangays"
on public.barangay
for select
using (public.is_admin());

create policy "Admins can read collection logs"
on public.collection_logs
for select
using (public.is_admin());

create policy "Admins can update collection logs"
on public.collection_logs
for update
using (public.is_admin())
with check (public.is_admin());

create policy "Admins can read collection schedules"
on public.collection_schedules
for select
using (public.is_admin());

create policy "Admins can update collection schedules"
on public.collection_schedules
for update
using (public.is_admin() or created_by = auth.uid())
with check (public.is_admin() or created_by = auth.uid());

create policy "Admins can insert collection schedules"
on public.collection_schedules
for insert
with check (public.is_admin() or created_by = auth.uid());

create policy "Admins can delete collection schedules"
on public.collection_schedules
for delete
using (public.is_admin() or created_by = auth.uid());

create policy "Admins can read users"
on public.users
for select
using (public.is_admin());

create policy "Admins can update users"
on public.users
for update
using (public.is_admin())
with check (public.is_admin());

create policy "Users can insert own profile"
on public.users
for insert
with check (id = auth.uid() or public.is_admin());

create policy "Users can read own profile"
on public.users
for select
using (id = auth.uid());

create policy "Users can update own profile"
on public.users
for update
using (id = auth.uid())
with check (id = auth.uid());

create policy "Admins can read waste reports"
on public.waste_reports
for select
using (public.is_admin());

create policy "Admins can update waste reports"
on public.waste_reports
for update
using (public.is_admin())
with check (public.is_admin());
