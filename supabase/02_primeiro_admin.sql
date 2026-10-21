-- Somente para um projeto NOVO sem administrador.
-- Crie a conta no Supabase Auth primeiro e substitua o e-mail abaixo.
-- No projeto recebimento-cargas atual, não é necessário executar este arquivo.
insert into public.perfis_manifestos(id,email,nome,perfil,ativo,proprietario)
select id,lower(email),'Administrador TD Cargas','admin',true,true
from auth.users where lower(email)=lower('SEU_EMAIL_ADMIN@EXEMPLO.COM')
on conflict(id) do nothing;
-- Confirme o cadastro:
select email,perfil,ativo from public.perfis_manifestos where proprietario;
