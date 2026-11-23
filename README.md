# database

Scripts do banco MySQL `adega_underground`, compartilhado pelo back-end e pelos microsserviços.

## Arquivos

| Arquivo | Uso |
|---|---|
| `script_create_database.sql` | Recria o banco **do zero**, com dados de exemplo. Começa com `DROP DATABASE`: **apaga tudo**. |
| `modelagem_database_adega_underground.mwb` | Modelagem no MySQL Workbench. |
| `validacao/diagnostico_pre_migracao.sql` | Só `SELECT`. Rode **antes** das migrations num banco com dados reais: lista duplicados, ml inválido, doses sem pai etc. |
| `validacao/cenarios_aceite_step0.sql` | Cenários de aceite (pagamento dividido, caixa, preço, ml...). Roda numa transação com `ROLLBACK`; todas as linhas devem mostrar `PASS`. |

## Banco novo

Execute o `script_create_database.sql` inteiro.

Pelo terminal, use sempre `mysql --default-character-set=utf8mb4 -u root -p < arquivo.sql`
(sem isso os acentos podem ser gravados errado). Os scripts já começam com `SET NAMES utf8mb4`.

## Banco já existente

1. Faça backup e rode `validacao/diagnostico_pre_migracao.sql`; corrija o que ele listar.
2. Execute, em ordem numérica, os scripts de `migrations/` que ainda não foram aplicados.
   Eles podem ser executados mais de uma vez sem erro.
3. A `008_triggers_historico_preco.sql` exige privilégio de trigger; com log binário ligado (ex.: RDS) pode
   falhar com erro 1419. Nesse caso não a execute: o histórico de preços passa a ser gravado pela aplicação.
4. A `005_backfill_valores_vendas.sql` deve ser executada de novo imediatamente antes de publicar o Step 2
   (vendas feitas pelo back-end antigo depois da 004 entram sem valor).
5. As migrations 003 a 010 só adicionam colunas com `NULL`/`DEFAULT` e novas tabelas: o back-end atual
   continua funcionando sem alteração de código.

## Convenção das migrations

- Nome: `NNN_descricao_em_snake_case.sql` (ex.: `001_create_notification_stock_alert_sent.sql`).
- Toda tabela nova entra no script principal **e** em uma migration.
- Uma migration já commitada nunca é editada; correções viram um novo número.
- Idempotência de `ALTER TABLE`: o MySQL não tem `ADD COLUMN IF NOT EXISTS`; as migrations 003+ criam
  procedures auxiliares (`adega_mig_*`) no início e as removem no fim. Constraints (`CHECK`, `UNIQUE`) que
  podem colidir com dados existentes só são criadas se nenhuma linha as violar; senão a migration mostra
  uma linha `AVISO` e segue. Corrija os dados e execute de novo.

## Tabelas do monólito acrescentadas no Step 0

| Tabela | Finalidade |
|---|---|
| `dmsao_forma_pagamento` | formas de pagamento normalizadas (`eh_dinheiro`, `gera_saldo_devedor`) |
| `evento_pagamento` | N pagamentos por evento: valor recebido, valor aplicado e troco |
| `caixa`, `movimento_caixa` | abertura/fechamento e movimentações (entrada adicional, sangria, devolução) |
| `historico_preco_produto` | preço anterior e novo, usuário, data e origem (trigger da `008`) |
| `movimento_volume` | ml por garrafa: abertura, venda, amostra, perda, ajuste |
| `movimento_estoque` | razão do estoque em unidades, com saldo anterior e posterior |
| `vw_caixa_resumo` (view) | esperado = fundo + dinheiro líquido + entradas - sangrias - devoluções |

## Tabelas dos microsserviços

| Tabela | Serviço | Finalidade |
|---|---|---|
| `daily_report_processed` | daily-report-service | 1 relatório por dia |
| `notification_stock_alert_sent` | notification-service | 1 alerta por produto por dia + trava contra envio duplicado |