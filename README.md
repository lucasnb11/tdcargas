# TD Cargas — Publicar no GitHub e na Vercel

Sistema web em português, com identidade azul (#0B315A) e laranja (#F58220), login Supabase, acesso por cidade, manifestos por viagem, conferência, recebimentos, Pix e backup.

## 1. Preparar o Supabase

Este pacote usa o Supabase para os usuários E para os dados. Os dados da versão hospedada anteriormente não são transferidos apenas ao publicar o código.

1. Abra o projeto Supabase que já utiliza. O projeto atual chama-se **recebimento-cargas**, ref `bdmogkdnhvstcgfuxznz`.
2. No **SQL Editor**, execute o conteúdo de `supabase/01_instalacao.sql`.
3. O script preserva as contas e perfis existentes e cria as tabelas `td_manifestos`, `td_cidades` e `td_config_pagamento`, além das permissões de acesso.
4. Em um projeto novo, crie o usuário administrador em **Authentication → Users** e execute `supabase/02_primeiro_admin.sql` após substituir o e-mail. No projeto atual, sua conta de administrador já existe.
5. A função `manifestos-create-city-user` já está publicada no projeto atual. Em outro projeto, publique a pasta `supabase/functions/manifestos-create-city-user` com esse nome, mantendo a verificação JWT ativada. O código está incluído no pacote. As variáveis `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `SUPABASE_SERVICE_ROLE_KEY` são disponibilizadas pelo ambiente das Edge Functions. A chave privilegiada fica somente na função, nunca na Vercel ou no navegador.

## 2. Subir para o GitHub

1. Extraia este ZIP.
2. Crie um repositório no GitHub e envie os arquivos da pasta `td-cargas-vercel` diretamente para a raiz do repositório.
3. Inclua os arquivos de configuração, como `.gitignore` e `.env.example`.
4. Não envie `node_modules`, `.next`, arquivos `.env.local` nem backups operacionais.

O pacote não contém senhas, chaves reais, sessões, PDFs de clientes nem dados operacionais. O worker local do PDF é uma dependência necessária para ler os manifestos.

## 3. Publicar na Vercel

1. Na Vercel, selecione **Add New → Project** e importe o repositório do GitHub.
2. Framework: **Next.js**. Root Directory: a pasta que contém `package.json` (normalmente a raiz).
3. Em **Environment Variables**, cadastre para Production e Preview:

| Variável | Valor |
| --- | --- |
| `SUPABASE_URL` | URL do seu projeto Supabase |
| `SUPABASE_PUBLISHABLE_KEY` | Chave Publishable do mesmo projeto |

Copie os valores no painel do Supabase. Use somente a chave publicável; não configure `service_role` neste aplicativo.

4. Node.js: **22.x**. O arquivo `vercel.json` configura instalação (`npm ci`) e build (`npm run build`).
5. Clique em **Deploy**. O login do sistema é por e-mail e senha do Supabase; não depende do login do ChatGPT.
6. Após a publicação, entre como administrador e confirme as cidades e os perfis.

Referências oficiais: https://vercel.com/docs/frameworks/full-stack/nextjs e https://vercel.com/docs/environment-variables

## 4. Migrar os dados da versão anterior

1. Entre como administrador na versão anterior do sistema.
2. Em **Viagens e manifestos**, clique em **Exportar backup**. Guarde o arquivo JSON em local protegido.
3. Na nova versão da Vercel, entre como administrador e clique em **Importar backup** na mesma tela.
4. A importação mantém manifestos, pagamentos, conferências, cidades cadastradas e a configuração Pix. Registros com IDs já existentes são preservados, sem sobrescrita.
5. O limite por importação é **3 MB**. Em backups maiores, divida os manifestos em mais de um arquivo JSON, mantendo `format`, `version`, `cities` e `settings`.
6. Usuários e senhas não fazem parte do backup: permanecem no Supabase Auth. Usando o mesmo projeto, os perfis também continuam disponíveis.

O backup contém informações de clientes e recebimentos. Não o envie ao GitHub.

## 5. Conferir a operação

- Administrador: todas as cidades, usuários, importação, financeiro e Pix.
- Entregador: apenas as cargas da cidade vinculada, conferência e baixa.
- Pagamento parcial exige justificativa. A confirmação fica registrada com o usuário autenticado.
- Gerar QR Code não confirma um pagamento; confira o recebimento antes da baixa.
- Os manifestos permanecem separados por viagem. A tela Pendências de pagamento exige uma viagem / manifesto selecionado e mostra somente seus saldos em aberto. A troca de manifesto também filtra o resumo e a exportação CSV.
- Em **Cidades → Nova cidade**, novos destinos ficam disponíveis para os usuários e a importação.

## Desenvolvimento local

Requisitos: Node.js 22 e npm.

```bash
npm ci
cp .env.example .env.local
# Preencha .env.local com a URL e a Publishable Key do Supabase.
npm run dev
```

Validações:

```bash
npm run typecheck
npm run build
```

No Windows, copie `.env.example` para `.env.local` pelo Explorador ou pelo editor. Nunca publique `.env.local`.

## Arquivos principais

- `app/`: interface e rotas do servidor Next.js.
- `lib/`: autenticação, dados, Pix, leitura de manifestos e regras de cidade.
- `supabase/`: instalação SQL, administrador inicial e função de criação de contas.
- `public/`: ícone e worker do leitor de PDF.
- `.env.example`: nomes das configurações necessárias.
- `package.json`, `package-lock.json`, `vercel.json`: instalação e publicação.

## Conhecimentos e clientes pagadores

- Em **Conhecimentos**, consulte todos os manifestos, filtre por cliente, destino ou situação e exporte o resultado.
- Em **Novo conhecimento**, selecione um manifesto existente e informe número, cliente pagador, destino, tipo, volumes e frete. O vínculo ao manifesto é obrigatório.
- O número não pode se repetir no mesmo manifesto. Somente administradores cadastram conhecimentos.
- **Clientes pagadores** reúne os conhecimentos e saldos por nome de cliente entre manifestos. Use o mesmo nome para manter o agrupamento; não há identificação por CPF/CNPJ nesta versão.
- Os pagamentos integrais e parciais continuam individuais; os totais do manifesto e do cliente são calculados a partir dos conhecimentos.
- Para instalar esta atualização em outro banco, execute também `supabase/03_conhecimentos.sql`.
- Validação local: `npm test`, `npm run typecheck` e `npm run build`.

## Justificativas de pagamento parcial

Ao selecionar Parcial, escolha Sem dinheiro, Acordo com administração, Pagamento parcelado ou Outros. O parcelamento exige a quantidade total de parcelas (inteiro a partir de 2); Outros exige descrição manual. O motivo e a quantidade informada ficam registrados no histórico e na exportação CSV, no campo de justificativa. Esta alteração registra a quantidade de parcelas, sem gerar vencimentos ou cobranças automáticas.

## Destinatários por manifesto

A lista principal agrupa os conhecimentos por destinatário dentro de cada manifesto. Clique no nome ou em Ver conhecimentos para expandir os documentos individuais. Nessa área ficam Conferir carga, Registrar pagamento / Dar baixa e, para administradores, Ver histórico. Cada pagamento mantém o vínculo ao conhecimento original e suas justificativas. A consulta de pendências mostra destinatários com saldo no manifesto selecionado; ao expandir, são mostrados todos os conhecimentos daquele destinatário no mesmo manifesto, inclusive os quitados. A exportação continua respeitando os filtros por conhecimento.

## Leitura em celular

Em telas até 760 px, as tabelas são apresentadas como cartões com rótulos. Destinatários e conhecimentos usam os mesmos dados e ações do desktop. Nomes completos podem ocupar várias linhas, e os botões de pagamento e histórico ficam abaixo dos valores. Filtros, seleção de manifesto e janelas se ajustam à largura disponível.
