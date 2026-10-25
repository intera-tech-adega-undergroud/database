# database

Scripts do banco MySQL `adega_underground`, compartilhado pelo back-end e pelos microsserviços.

## Arquivos

| Arquivo | Uso |
|---|---|
| `script_create_database.sql` | Recria o banco **do zero**, com dados de exemplo. Começa com `DROP DATABASE`: **apaga tudo**. |
| `modelagem_database_adega_underground.mwb` | Modelagem no MySQL Workbench. |

## Banco novo

Execute o `script_create_database.sql` inteiro.

## Banco já existente

Execute, em ordem numérica, os scripts de `migrations/` que ainda não foram aplicados.
Eles podem ser executados mais de uma vez sem erro.

## Convenção das migrations

- Nome: `NNN_descricao_em_snake_case.sql` (ex.: `001_create_notification_stock_alert_sent.sql`).
- Toda tabela nova entra no script principal **e** em uma migration.
- Uma migration já commitada nunca é editada; correções viram um novo número.

## Tabelas dos microsserviços

| Tabela | Serviço | Finalidade |
|---|---|---|
| `daily_report_processed` | daily-report-service | 1 relatório por dia |
| `notification_stock_alert_sent` | notification-service | 1 alerta por produto por dia + trava contra envio duplicado |