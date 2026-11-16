# Segundo Cérebro · Aprenda lendo

Página única (`index.html`) para ler um pouco todo dia, guardar o que aprendeu (5 Cs: captar, categorizar, condensar, concretizar, catalogar), ver métricas, compartilhar a ofensiva no Instagram e conversar sobre livros na comunidade.

## Como ligar o login e a comunidade (Supabase)

1. Crie um projeto em supabase.com (região South America, São Paulo).
2. No **SQL Editor**, rode nesta ordem: `supabase/01-conta.sql` e `supabase/02-comunidade.sql`.
3. Em **Project Settings > API**, copie o **Project URL** e a chave **anon public**.
4. No `index.html`, preencha `SB_URL` e `SB_KEY` (procure por `const SB_URL`).
5. Em **Authentication > URL Configuration**, coloque o endereço publicado da página.

Sem as chaves, o app funciona sem login e salva só no aparelho.

## Moderação

Posts, comentários e temas denunciados por 3 pessoas diferentes ficam ocultos. Para revisar, veja o fim de `supabase/02-comunidade.sql`.

---
© 2026 Cristiane Queiroz. Todos os direitos reservados.
