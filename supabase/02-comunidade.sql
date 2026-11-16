-- Segundo Cérebro: comunidade (rodar uma vez no SQL Editor do Supabase, depois do 01-conta.sql)

create table if not exists perfis_publicos (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  apelido text not null check (apelido ~ '^[A-Za-z0-9_.À-ÿ]{3,20}$'),
  emoji text not null default '📚' check (char_length(emoji) <= 8),
  maior_de_18 boolean not null default true check (maior_de_18),
  created_at timestamptz not null default now()
);
create unique index if not exists perfis_publicos_apelido on perfis_publicos (lower(apelido));

create table if not exists livros_comunidade (
  id uuid primary key default gen_random_uuid(),
  titulo text not null check (char_length(titulo) between 1 and 120),
  autor text not null default '' check (char_length(autor) <= 120),
  criado_por uuid default auth.uid() references perfis_publicos(user_id) on delete set null,
  oculto boolean not null default false,
  ultimo_post_em timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create unique index if not exists livros_comunidade_unico on livros_comunidade (lower(titulo), lower(autor));
create index if not exists livros_comunidade_recentes on livros_comunidade (ultimo_post_em desc);

create table if not exists posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references perfis_publicos(user_id) on delete cascade,
  livro_id uuid not null references livros_comunidade on delete cascade,
  tipo text not null default 'insight' check (tipo in ('insight', 'pratica', 'consenso', 'duvida', 'opiniao')),
  nota int check (nota between 1 and 5),
  texto text not null check (char_length(texto) between 1 and 1000),
  oculto boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists posts_created on posts (created_at desc);
create index if not exists posts_livro on posts (livro_id, created_at desc);

create table if not exists comentarios (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts on delete cascade,
  user_id uuid not null default auth.uid() references perfis_publicos(user_id) on delete cascade,
  texto text not null check (char_length(texto) between 1 and 500),
  oculto boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists comentarios_post on comentarios (post_id, created_at);

create table if not exists curtidas (
  post_id uuid not null references posts on delete cascade,
  user_id uuid not null default auth.uid() references perfis_publicos(user_id) on delete cascade,
  primary key (post_id, user_id)
);

create table if not exists denuncias (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('post', 'comentario', 'livro')),
  alvo_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  motivo text check (char_length(motivo) <= 200),
  created_at timestamptz not null default now(),
  unique (tipo, alvo_id, user_id)
);

create table if not exists bloqueios (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  bloqueado_id uuid not null references auth.users on delete cascade,
  primary key (user_id, bloqueado_id),
  check (user_id <> bloqueado_id)
);

-- Função privada (fora do esquema público, então não aparece na API): há bloqueio entre as duas pessoas, em qualquer sentido?
create schema if not exists private;
grant usage on schema private to authenticated;
create or replace function private.bloqueado_entre(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from bloqueios where (user_id = a and bloqueado_id = b) or (user_id = b and bloqueado_id = a));
$$;
revoke all on function private.bloqueado_entre(uuid, uuid) from public;
grant execute on function private.bloqueado_entre(uuid, uuid) to authenticated;

alter table perfis_publicos enable row level security;
alter table livros_comunidade enable row level security;
alter table posts enable row level security;
alter table comentarios enable row level security;
alter table curtidas enable row level security;
alter table denuncias enable row level security;
alter table bloqueios enable row level security;

create policy "ver perfis" on perfis_publicos for select to authenticated using (true);
create policy "criar meu perfil" on perfis_publicos for insert to authenticated with check (user_id = auth.uid());
create policy "editar meu perfil" on perfis_publicos for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "apagar meu perfil" on perfis_publicos for delete to authenticated using (user_id = auth.uid());

create policy "ver livros" on livros_comunidade for select to authenticated using (not oculto);
create policy "criar livro" on livros_comunidade for insert to authenticated with check (criado_por = auth.uid());

create policy "ver posts" on posts for select to authenticated using (
  not oculto and not private.bloqueado_entre(auth.uid(), user_id));
create policy "criar post" on posts for insert to authenticated with check (user_id = auth.uid());
create policy "apagar meu post" on posts for delete to authenticated using (user_id = auth.uid());

create policy "ver comentarios" on comentarios for select to authenticated using (
  not oculto and not private.bloqueado_entre(auth.uid(), user_id));
-- só dá para comentar e curtir em posts que a pessoa consegue ver (ou seja, sem bloqueio nem ocultos)
create policy "criar comentario" on comentarios for insert to authenticated with check (
  user_id = auth.uid() and exists (select 1 from posts p where p.id = post_id));
create policy "apagar meu comentario" on comentarios for delete to authenticated using (user_id = auth.uid());

create policy "ver curtidas" on curtidas for select to authenticated using (true);
create policy "curtir" on curtidas for insert to authenticated with check (
  user_id = auth.uid() and exists (select 1 from posts p where p.id = post_id));
create policy "descurtir" on curtidas for delete to authenticated using (user_id = auth.uid());

create policy "denunciar" on denuncias for insert to authenticated with check (user_id = auth.uid());

create policy "meus bloqueios" on bloqueios for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Posts, comentários e temas de livro denunciados por 3 pessoas diferentes ficam ocultos até você revisar.
create or replace function ocultar_se_muitas_denuncias() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from denuncias where tipo = new.tipo and alvo_id = new.alvo_id) >= 3 then
    if new.tipo = 'post' then update posts set oculto = true where id = new.alvo_id;
    elsif new.tipo = 'livro' then update livros_comunidade set oculto = true where id = new.alvo_id;
    else update comentarios set oculto = true where id = new.alvo_id; end if;
  end if;
  return new;
end $$;
drop trigger if exists t_denuncia on denuncias;
create trigger t_denuncia after insert on denuncias for each row execute function ocultar_se_muitas_denuncias();

-- Quando alguém publica, o tema do livro sobe na lista.
create or replace function atualizar_livro() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update livros_comunidade set ultimo_post_em = now() where id = new.livro_id;
  return new;
end $$;
drop trigger if exists t_atualiza_livro on posts;
create trigger t_atualiza_livro after insert on posts for each row execute function atualizar_livro();

-- Limites contra spam: 10 posts, 30 comentários e 5 temas de livro por hora, por pessoa.
create or replace function limitar_livros() returns trigger language plpgsql as $$
begin
  if (select count(*) from livros_comunidade where criado_por = new.criado_por and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'limite de livros por hora';
  end if;
  return new;
end $$;
drop trigger if exists t_limite_livros on livros_comunidade;
create trigger t_limite_livros before insert on livros_comunidade for each row execute function limitar_livros();

create or replace function limitar_posts() returns trigger language plpgsql as $$
begin
  if (select count(*) from posts where user_id = new.user_id and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'limite de posts por hora';
  end if;
  return new;
end $$;
drop trigger if exists t_limite_posts on posts;
create trigger t_limite_posts before insert on posts for each row execute function limitar_posts();

create or replace function limitar_comentarios() returns trigger language plpgsql as $$
begin
  if (select count(*) from comentarios where user_id = new.user_id and created_at > now() - interval '1 hour') >= 30 then
    raise exception 'limite de comentarios por hora';
  end if;
  return new;
end $$;
drop trigger if exists t_limite_comentarios on comentarios;
create trigger t_limite_comentarios before insert on comentarios for each row execute function limitar_comentarios();

-- Para revisar o que foi denunciado (no SQL Editor):
--   select tipo, alvo_id, count(*) as denuncias, array_agg(motivo) from denuncias group by 1, 2 order by 3 desc;
-- Para ocultar ou apagar:
--   update posts set oculto = true where id = '...';   |   delete from posts where id = '...';
--   update livros_comunidade set oculto = true where id = '...';
