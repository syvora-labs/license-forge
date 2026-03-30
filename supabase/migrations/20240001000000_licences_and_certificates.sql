-- Migration: licences_and_certificates
-- Created: 2026-03-30

create table public.licences (
    id          uuid primary key default gen_random_uuid(),
    uid         uuid not null references auth.users(id) on delete cascade,
    licence_name    text not null,
    expiration_date date not null,
    reminder_date   date,
    created_at  timestamptz default now()
);

create table public.certificates (
    id          uuid primary key default gen_random_uuid(),
    uid         uuid not null references auth.users(id) on delete cascade,
    certificate_name text not null,
    expiration_date  date not null,
    reminder_date    date,
    created_at   timestamptz default now()
);

-- Indexes for fast user lookups
create index on public.licences (uid);
create index on public.certificates (uid);

-- RLS
alter table public.licences    enable row level security;
alter table public.certificates enable row level security;

create policy "Users can manage their own licences"
    on public.licences
    for all
    using (auth.uid() = uid);

create policy "Users can manage their own certificates"
    on public.certificates
    for all
    using (auth.uid() = uid);