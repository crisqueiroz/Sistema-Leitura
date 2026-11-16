-- Segundo Cérebro: dados de leitura por conta (rodar uma vez no SQL Editor do Supabase)
create table if not exists dados (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  key text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table dados enable row level security;
drop policy if exists "so o dono" on dados;
create policy "so o dono" on dados for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
