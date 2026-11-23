-- 009. Estoque, garrafas abertas (ml) e concorrência || Monólito (back-end)  [Step 0 / itens #5, #7, #18]
-- - versao em tbl_produto e tbl_unidade_bebida: base do lock otimista (@Version) do Step 3.
-- - tbl_unidade_bebida: status ESGOTADA (garrafa vazia deixa de parecer "FECHADA"), aberta_em/esgotada_em
--   e CHECKs de integridade: 0 <= ml_atual <= ml_inicial e ESGOTADA => ml_atual = 0.
--   Os CHECKs só entram se nenhuma linha atual os violar (veja validacao/diagnostico_pre_migracao.sql).
-- - movimento_volume: cada saída/entrada de ml por garrafa (venda, amostra, perda, ajuste, abertura),
--   com ml anterior/posterior. As doses continuam sendo produtos filhos (id_produto_pai).
-- - movimento_estoque: razão do estoque em unidades (entrada, venda, cancelamento, perda, amostra,
--   ajuste, abertura de garrafa), com saldo anterior/posterior; o saldo pode ser negativo.
-- Nenhuma regra de saldo >= 0 em tbl_produto: estoque negativo segue como decisão do Step 3.
-- As tabelas de movimento são alimentadas pelo back-end nos Steps 3 e 5. FKs sem CASCADE: produto ou
-- garrafa com movimento deve ser inativado, não excluído.
-- Compatível com o back-end atual: colunas novas com DEFAULT/NULL; nenhuma linha usa ESGOTADA ainda
-- (o enum Java StatusBebida só ganha o valor no Step 5; não crie linhas ESGOTADA antes disso).
-- Idempotente: pode ser executado mais de uma vez sem erro.
USE adega_underground;
SET NAMES utf8mb4;

-- ---------------------------------------------------------------------------
-- Auxiliares de idempotência (criados e removidos dentro deste script; nada fica no banco).
-- ---------------------------------------------------------------------------
DELIMITER $$

DROP PROCEDURE IF EXISTS adega_mig_add_column$$
CREATE PROCEDURE adega_mig_add_column(IN p_table VARCHAR(64), IN p_column VARCHAR(64), IN p_definition TEXT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND COLUMN_NAME = p_column) THEN
        SET @adega_sql = CONCAT('ALTER TABLE `', p_table, '` ADD COLUMN `', p_column, '` ', p_definition);
        PREPARE adega_stmt FROM @adega_sql;
        EXECUTE adega_stmt;
        DEALLOCATE PREPARE adega_stmt;
    END IF;
END$$

DROP PROCEDURE IF EXISTS adega_mig_add_index$$
CREATE PROCEDURE adega_mig_add_index(IN p_table VARCHAR(64), IN p_index VARCHAR(64), IN p_columns VARCHAR(255))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND INDEX_NAME = p_index) THEN
        SET @adega_sql = CONCAT('CREATE INDEX `', p_index, '` ON `', p_table, '` (', p_columns, ')');
        PREPARE adega_stmt FROM @adega_sql;
        EXECUTE adega_stmt;
        DEALLOCATE PREPARE adega_stmt;
    END IF;
END$$

-- Chave estrangeira ou CHECK: p_tail é o que vem depois de "ADD CONSTRAINT <nome> ".
DROP PROCEDURE IF EXISTS adega_mig_add_constraint$$
CREATE PROCEDURE adega_mig_add_constraint(IN p_table VARCHAR(64), IN p_name VARCHAR(64), IN p_tail TEXT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
                   WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND CONSTRAINT_NAME = p_name) THEN
        SET @adega_sql = CONCAT('ALTER TABLE `', p_table, '` ADD CONSTRAINT `', p_name, '` ', p_tail);
        PREPARE adega_stmt FROM @adega_sql;
        EXECUTE adega_stmt;
        DEALLOCATE PREPARE adega_stmt;
    END IF;
END$$

-- CHECK que só entra se nenhuma linha atual o violar (p_violation = condição das linhas ruins).
DROP PROCEDURE IF EXISTS adega_mig_add_check_if_clean$$
CREATE PROCEDURE adega_mig_add_check_if_clean(IN p_table VARCHAR(64), IN p_name VARCHAR(64),
                                              IN p_expr TEXT, IN p_violation TEXT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
                   WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND CONSTRAINT_NAME = p_name) THEN
        SET @adega_sql = CONCAT('SELECT COUNT(*) INTO @adega_violacoes FROM `', p_table, '` WHERE ', p_violation);
        PREPARE adega_stmt FROM @adega_sql;
        EXECUTE adega_stmt;
        DEALLOCATE PREPARE adega_stmt;
        IF @adega_violacoes = 0 THEN
            SET @adega_sql = CONCAT('ALTER TABLE `', p_table, '` ADD CONSTRAINT `', p_name, '` CHECK (', p_expr, ')');
            PREPARE adega_stmt FROM @adega_sql;
            EXECUTE adega_stmt;
            DEALLOCATE PREPARE adega_stmt;
        ELSE
            SELECT CONCAT('AVISO: constraint ', p_name, ' NAO criada; ', @adega_violacoes,
                          ' linha(s) de ', p_table, ' violam a regra. Rode validacao/diagnostico_pre_migracao.sql, corrija e execute de novo.') AS aviso;
        END IF;
    END IF;
END$$

-- UNIQUE que só entra se não houver valores repetidos (NULL é ignorado).
DROP PROCEDURE IF EXISTS adega_mig_add_unique_if_clean$$
CREATE PROCEDURE adega_mig_add_unique_if_clean(IN p_table VARCHAR(64), IN p_index VARCHAR(64), IN p_column VARCHAR(64))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND INDEX_NAME = p_index) THEN
        SET @adega_sql = CONCAT('SELECT COUNT(*) INTO @adega_violacoes FROM (SELECT `', p_column, '` FROM `', p_table,
                                '` WHERE `', p_column, '` IS NOT NULL GROUP BY `', p_column, '` HAVING COUNT(*) > 1) d');
        PREPARE adega_stmt FROM @adega_sql;
        EXECUTE adega_stmt;
        DEALLOCATE PREPARE adega_stmt;
        IF @adega_violacoes = 0 THEN
            SET @adega_sql = CONCAT('ALTER TABLE `', p_table, '` ADD CONSTRAINT `', p_index, '` UNIQUE (`', p_column, '`)');
            PREPARE adega_stmt FROM @adega_sql;
            EXECUTE adega_stmt;
            DEALLOCATE PREPARE adega_stmt;
        ELSE
            SELECT CONCAT('AVISO: UNIQUE ', p_index, ' NAO criado; ', @adega_violacoes,
                          ' valor(es) repetido(s) em ', p_table, '.', p_column, '. Rode validacao/diagnostico_pre_migracao.sql.') AS aviso;
        END IF;
    END IF;
END$$

DELIMITER ;


CALL adega_mig_add_column('tbl_produto', 'versao', 'INT NOT NULL DEFAULT 0');
CALL adega_mig_add_column('tbl_unidade_bebida', 'versao', 'INT NOT NULL DEFAULT 0');
CALL adega_mig_add_column('tbl_unidade_bebida', 'aberta_em', 'DATETIME NULL');
CALL adega_mig_add_column('tbl_unidade_bebida', 'esgotada_em', 'DATETIME NULL');

ALTER TABLE tbl_unidade_bebida
    MODIFY COLUMN status ENUM('ABERTO','FECHADO','ESGOTADA') DEFAULT 'FECHADO';

CALL adega_mig_add_check_if_clean('tbl_unidade_bebida', 'chk_unidade_volume',
    '(ml_inicial IS NULL OR ml_inicial > 0) AND (ml_atual IS NULL OR ml_atual >= 0) AND (ml_inicial IS NULL OR ml_atual IS NULL OR ml_atual <= ml_inicial)',
    '(ml_inicial IS NOT NULL AND ml_inicial <= 0) OR (ml_atual IS NOT NULL AND ml_atual < 0) OR (ml_inicial IS NOT NULL AND ml_atual IS NOT NULL AND ml_atual > ml_inicial)');
CALL adega_mig_add_check_if_clean('tbl_unidade_bebida', 'chk_unidade_esgotada',
    'status <> ''ESGOTADA'' OR ml_atual = 0',
    'status = ''ESGOTADA'' AND (ml_atual IS NULL OR ml_atual <> 0)');

CREATE TABLE IF NOT EXISTS movimento_volume (
    id_movimento_volume INT PRIMARY KEY AUTO_INCREMENT,
    id_unidade_bebida INT NOT NULL,
    tipo ENUM('ABERTURA','VENDA','AMOSTRA','PERDA','AJUSTE') NOT NULL,
    ml_delta INT NOT NULL,
    ml_anterior INT NOT NULL,
    ml_posterior INT NOT NULL,
    id_produto_vendido INT NULL,
    id_evento INT NULL,
    id_funcionario INT NULL,
    motivo VARCHAR(255) NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_movimento_volume_unidade FOREIGN KEY (id_unidade_bebida) REFERENCES tbl_unidade_bebida(id_unidade_bebida),
    CONSTRAINT fk_movimento_volume_produto FOREIGN KEY (id_produto_vendido) REFERENCES tbl_produto(id_produto),
    CONSTRAINT fk_movimento_volume_evento FOREIGN KEY (id_evento) REFERENCES tbl_evento(id_evento),
    CONSTRAINT fk_movimento_volume_funcionario FOREIGN KEY (id_funcionario) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT chk_movimento_volume_saldo CHECK (ml_posterior >= 0 AND ml_posterior = ml_anterior + ml_delta),
    CONSTRAINT chk_movimento_volume_sentido CHECK (
        (tipo IN ('VENDA','AMOSTRA','PERDA') AND ml_delta < 0)
        OR (tipo = 'ABERTURA' AND ml_delta = 0)
        OR tipo = 'AJUSTE')
);

CALL adega_mig_add_index('movimento_volume', 'idx_movimento_volume_unidade', 'id_unidade_bebida, criado_em');
CALL adega_mig_add_index('movimento_volume', 'idx_movimento_volume_evento', 'id_evento');

CREATE TABLE IF NOT EXISTS movimento_estoque (
    id_movimento_estoque INT PRIMARY KEY AUTO_INCREMENT,
    id_produto INT NOT NULL,
    tipo ENUM('ENTRADA','VENDA','CANCELAMENTO','PERDA','AMOSTRA','AJUSTE','ABERTURA_GARRAFA') NOT NULL,
    quantidade_delta INT NOT NULL,
    saldo_anterior INT NOT NULL,
    saldo_posterior INT NOT NULL,
    id_evento INT NULL,
    id_funcionario INT NULL,
    motivo VARCHAR(255) NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_movimento_estoque_produto FOREIGN KEY (id_produto) REFERENCES tbl_produto(id_produto),
    CONSTRAINT fk_movimento_estoque_evento FOREIGN KEY (id_evento) REFERENCES tbl_evento(id_evento),
    CONSTRAINT fk_movimento_estoque_funcionario FOREIGN KEY (id_funcionario) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT chk_movimento_estoque_saldo CHECK (saldo_posterior = saldo_anterior + quantidade_delta)
);

CALL adega_mig_add_index('movimento_estoque', 'idx_movimento_estoque_produto', 'id_produto, criado_em');
CALL adega_mig_add_index('movimento_estoque', 'idx_movimento_estoque_evento', 'id_evento');


DELIMITER $$
DROP PROCEDURE IF EXISTS adega_mig_add_column$$
DROP PROCEDURE IF EXISTS adega_mig_add_index$$
DROP PROCEDURE IF EXISTS adega_mig_add_constraint$$
DROP PROCEDURE IF EXISTS adega_mig_add_check_if_clean$$
DROP PROCEDURE IF EXISTS adega_mig_add_unique_if_clean$$
DELIMITER ;

