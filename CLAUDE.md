# CLAUDE.md — database

## Este repositório

- `script_create_database.sql`: script único e manual que **recria o banco do zero** (começa com
  `DROP DATABASE`), cria as tabelas e insere os dados de exemplo. Não há Flyway nem Liquibase.
- `modelagem_database_adega_underground.mwb`: modelagem do MySQL Workbench (binário, não edite).
- Fluxo Git: trabalho em **branch**, nunca direto na `main`. Branch desta entrega:
  `feat/notification-stock-alert-table` (Etapa 1).

## Regras para alterações de schema

- Toda tabela nova entra em **dois lugares**:
  1. no `script_create_database.sql`, na seção de tabelas, numerada na sequência das existentes;
  2. num script incremental em `migrations/`, para quem já tem o banco com dados. Regras do incremental:
     nome `NNN_descricao_em_snake_case.sql` (número sequencial com 3 dígitos), começa com
     `USE adega_underground;`, só `CREATE ... IF NOT EXISTS`/`ALTER`, nunca `DROP DATABASE`, e pode ser
     executado mais de uma vez sem erro. Um script já commitado nunca é editado: correções viram um novo número.
- Os serviços usam `ddl-auto: validate`: o schema do script precisa bater exatamente com o mapeamento JPA.
- Tabelas de microsserviços não têm FK para tabelas do monólito (desacoplamento).
- Não altere tabelas existentes nem os `INSERT` de exemplo, a menos que a etapa peça.

## Tabelas de microsserviços

| Tabela | Serviço | Finalidade |
|---|---|---|
| `daily_report_processed` | daily-report-service | idempotência: 1 relatório por `reference_date` |
| `notification_stock_alert_sent` | notification-service | trava + registro: 1 alerta por produto por dia (Etapa 1) |

Colunas de `notification_stock_alert_sent`: `product_id INT`, `reference_date DATE`,
`event_id CHAR(36) NOT NULL`, `severity VARCHAR(20) NOT NULL` (CHECK: `CRITICAL`, `HIGH`, `MEDIUM`),
`sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP`, chave primária (`product_id`, `reference_date`).
Script incremental: `migrations/001_create_notification_stock_alert_sent.sql`.

Como a trava usa essa tabela: o serviço abre a transação e faz o `INSERT` da linha (produto, dia) antes de
enviar o e-mail. Uma segunda transação com a mesma chave fica bloqueada nesse `INSERT` até a primeira terminar:
se a primeira fizer commit, a segunda recebe chave duplicada e não envia; se a primeira fizer rollback (falha
no envio), a segunda insere e envia.

## Contexto do projeto

Understock é o ERP próprio da **Adega Underground** (varejo de bebidas), desenvolvido pela equipe Intera
(trabalho acadêmico SPTech, em Sprints) para substituir o ERP pago CPlug.
Stack: Java 21, Spring Boot, MySQL 8.4 (banco único `adega_underground`), React 19, RabbitMQ.
Persona gestor: Junior (dono). Persona operador: João Victor.

Repositórios da organização `intera-tech-adega-undergroud`:
`back-end` (monólito), `daily-report-service`, `notification-service`, `database`, `front-end-react`.

## Como trabalhar neste repositório

- O desenvolvedor segue um step-by-step dividido em **etapas numeradas**. Execute **somente a etapa pedida**.
  Não antecipe etapas seguintes nem altere código fora do escopo da etapa.
- **Nunca faça `git commit`, `git push`, merge ou troca de branch.** O desenvolvedor faz isso manualmente.
- **Decisões de arquitetura não são tomadas por você.** Se surgir uma escolha que não esteja registrada
  neste arquivo, pare e siga o fluxo: (1) contextualize o problema em 1-2 frases; (2) apresente 2-3 opções;
  (3) trade-offs de cada uma em manutenibilidade/acoplamento, desempenho/escalabilidade e esforço;
  (4) recomende uma e **aguarde aprovação** antes de escrever código.
- Se faltar informação, pergunte. Não invente nomes, valores ou regras.
- Ambiente: **Windows + PowerShell + Docker Desktop**. Use `.\mvnw.cmd` para o Maven.
- Responda e documente em **português**. Nomes de classes, métodos e pacotes em inglês.
- Commits seguem Conventional Commits: tipo em inglês, descrição em português
  (ex.: `feat(messaging): adiciona consumidor RabbitMQ com retry e DLQ`). Você só sugere a mensagem.

## Segurança

- Nunca escreva senhas, tokens ou chaves em arquivos versionados, nem como valor padrão em
  `application.yml`/`application.properties`. Use variáveis de ambiente sem default para segredos.
- Nunca leia, exiba ou edite arquivos `.env`. Para documentar variáveis, edite `.env.example` com valores fictícios.
- Não peça nem aceite a senha de app do Gmail ou a senha do MySQL no chat.

## Padrões de código obrigatórios

**Clean Architecture (backend)**
- Entidades de domínio são puras: sem `@Entity`, `@Table`, `@Autowired` ou qualquer anotação Spring.
- Fluxo: Adapter de entrada → Input Port (Use Case) → domínio → Output Ports → Adapters de saída.
- DTOs e retornos imutáveis como `record`.
- Aplique Design Patterns quando resolverem o problema de negócio (Observer, Adapter, Strategy...).

**Mensageria**
- O broker fica isolado em Adapters. O listener só desserializa e chama o Use Case. O domínio e os
  Use Cases não conhecem RabbitMQ (requisito: trocar de broker no futuro deve exigir só um adapter novo).
- Tratamento de falha local com try/catch e logs estruturados (chave=valor, com `eventId`).
- Retry com atraso via **TTL + DLX nativo** (sem plugin), e DLQ ao esgotar as tentativas.
  Payload inválido vai direto para a DLQ, sem retry.
- Idempotência obrigatória antes de executar a lógica de negócio (chave no banco).

**E-mail (SOLID)**
- SRP: orquestração, renderização de template e envio SMTP em classes distintas.
- DIP: o núcleo depende de `EmailSenderPort` e `TemplateRendererPort`; `JavaMailSender` só na infraestrutura.
- OCP: múltiplos tipos de mensagem/relatório via Strategy.

## Decisões de arquitetura aprovadas (não rediscutir)

| # | Decisão |
|---|---|
| D1 | O agendamento das **23h59 (America/Sao_Paulo)** fica no monólito, que publica a solicitação do relatório diário no RabbitMQ. O Daily Report é só consumidor. |
| D2 | O monólito publica eventos **somente após o commit** (`@TransactionalEventListener(phase = AFTER_COMMIT)`), com publisher confirms e nova tentativa na publicação. Outbox fica como evolução futura. |
| D3 | Retry com atraso via **TTL + DLX nativo**: 3 tentativas com atrasos crescentes (30s, 2min, 10min) e depois DLQ. |
| D4 | O `docker-compose.yml` do RabbitMQ fica na raiz do repositório `back-end`. |
| D5 | Trava contra envio concorrente: **trava pessimista no banco** — chave única (produto, dia) + `SELECT ... FOR UPDATE` durante o envio. |
| D6 | O Kafka será removido do projeto inteiro. A migração do Daily Report para RabbitMQ acontece **depois** do Notification Service, nesta mesma entrega. |

## Regras de negócio

- Estoque negativo é **permitido** (venda antes de a entrada ser registrada). A venda nunca é bloqueada por saldo.
- Alerta em tempo real de estoque: **no máximo 1 alerta por produto por dia** (dia do calendário em
  America/Sao_Paulo), qualquer que seja a gravidade. Um alerta crítico não "fura" o limite.
- Só geram alerta em tempo real produtos das categorias `BEBIDA_UNIDADE` e `DIVERSOS`.
  Fracionados (doses), drinks e combos não geram; componentes de combo são verificados individualmente.
  Alertas de garrafas fracionadas quase vazias existem apenas no Daily Report.
- Gravidade (calculada no domínio do Notification Service):

| Condição | Gravidade | Mensagem |
|---|---|---|
| saldo < 0 | `CRITICAL` | Estoque negativo, provável entrada não registrada |
| saldo = 0 | `HIGH` | Estoque zerado |
| 0 < saldo ≤ mínimo | `MEDIUM` | Estoque abaixo do mínimo |

- O fechamento diário real é às **23h59 (America/Sao_Paulo)** e cobre o dia do calendário.
- Destinatário dos e-mails: a Diretoria (mesmo destinatário do Daily Report).
- WhatsApp e front-end estão **fora do escopo** desta entrega.

## Contrato do evento de alerta de estoque

Publicado pelo monólito, consumido pelo Notification Service. É autossuficiente: o consumidor nunca
consulta o banco do monólito para montar o alerta.

| Campo | Tipo | Observação |
|---|---|---|
| `eventId` | UUID (string) | gerado pelo publicador |
| `productId` | inteiro | `tbl_produto.id_produto` |
| `productName` | string | |
| `currentQuantity` | inteiro | pode ser negativo |
| `minimumQuantity` | inteiro | |
| `occurredAt` | ISO-8601 com offset | instante da venda |

## Topologia RabbitMQ (vhost `adega`)

- Exchange `adega.stock.events` (topic, durável), routing key `stock.below-minimum`.
- Fila principal `notification.stock-alert` (ack manual).
- Filas de espera `notification.stock-alert.wait.30s`, `.wait.2m`, `.wait.10m` (sem consumidor; TTL + DLX
  devolvendo para a fila principal). Contador de tentativas no header `x-retry-count`.
- DLQ `notification.stock-alert.dlq`.
- Topologia do relatório diário: **a definir na Parte A** (não criar antes).
