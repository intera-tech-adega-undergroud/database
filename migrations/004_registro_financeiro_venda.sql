-- 004. Registro financeiro da venda || Monólito (back-end)  [Step 0 / itens #2, #3, #11]
-- Estrutura para: preço praticado congelado na venda, desconto, total e pagamento dividido.
-- - dmsao_forma_pagamento: formas normalizadas (eh_dinheiro separa dinheiro de eletrônico no caixa).
-- - evento_pagamento: N pagamentos por evento (valor recebido, valor aplicado e troco). Também serve
--   para RECEBIMENTO de fiado, que entra no caixa se for em dinheiro.
-- - tbl_evento / item_evento: colunas novas de valores, desconto, status e cancelamento.
-- Compatível com o back-end atual: toda coluna nova é NULL ou tem DEFAULT; tbl_evento.forma_pagamento
-- e tbl_evento.pago continuam existindo. O endurecimento (NOT NULL) fica para o Step 2.
-- O preenchimento das vendas antigas está em 005_backfill_valores_vendas.sql.
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


CREATE TABLE IF NOT EXISTS dmsao_forma_pagamento (
    id_forma_pagamento INT PRIMARY KEY AUTO_INCREMENT,
    codigo VARCHAR(20) NOT NULL,
    descricao VARCHAR(45) NOT NULL,
    eh_dinheiro TINYINT(1) NOT NULL DEFAULT 0,
    gera_saldo_devedor TINYINT(1) NOT NULL DEFAULT 0,
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    CONSTRAINT uq_forma_pagamento_codigo UNIQUE (codigo)
);

INSERT IGNORE INTO dmsao_forma_pagamento (codigo, descricao, eh_dinheiro, gera_saldo_devedor) VALUES
('DINHEIRO', 'Dinheiro', 1, 0),
('PIX', 'Pix', 0, 0),
('DEBITO', 'Cartão de Débito', 0, 0),
('CREDITO', 'Cartão de Crédito', 0, 0),
('FIADO', 'Fiado', 0, 1);

CALL adega_mig_add_column('tbl_evento', 'id_funcionario_executor', 'INT NULL');
CALL adega_mig_add_column('tbl_evento', 'subtotal', 'DECIMAL(10,2) NULL');
CALL adega_mig_add_column('tbl_evento', 'desconto_tipo', 'ENUM(''VALOR'',''PERCENTUAL'') NULL');
CALL adega_mig_add_column('tbl_evento', 'desconto_percentual', 'DECIMAL(5,2) NULL');
CALL adega_mig_add_column('tbl_evento', 'desconto_valor', 'DECIMAL(10,2) NOT NULL DEFAULT 0');
CALL adega_mig_add_column('tbl_evento', 'id_funcionario_desconto', 'INT NULL');
CALL adega_mig_add_column('tbl_evento', 'total', 'DECIMAL(10,2) NULL');
CALL adega_mig_add_column('tbl_evento', 'status', 'ENUM(''CONCLUIDA'',''CANCELADA'') NOT NULL DEFAULT ''CONCLUIDA''');
CALL adega_mig_add_column('tbl_evento', 'cancelado_em', 'DATETIME NULL');
CALL adega_mig_add_column('tbl_evento', 'id_funcionario_cancelamento', 'INT NULL');
CALL adega_mig_add_column('tbl_evento', 'motivo_cancelamento', 'VARCHAR(255) NULL');
CALL adega_mig_add_column('tbl_evento', 'valores_estimados', 'TINYINT(1) NOT NULL DEFAULT 0');

CALL adega_mig_add_constraint('tbl_evento', 'fk_evento_executor',
    'FOREIGN KEY (id_funcionario_executor) REFERENCES tbl_funcionario(id_funcionario)');
CALL adega_mig_add_constraint('tbl_evento', 'fk_evento_func_desconto',
    'FOREIGN KEY (id_funcionario_desconto) REFERENCES tbl_funcionario(id_funcionario)');
CALL adega_mig_add_constraint('tbl_evento', 'fk_evento_func_cancelamento',
    'FOREIGN KEY (id_funcionario_cancelamento) REFERENCES tbl_funcionario(id_funcionario)');

CALL adega_mig_add_constraint('tbl_evento', 'chk_evento_desconto_valor', 'CHECK (desconto_valor >= 0)');
CALL adega_mig_add_constraint('tbl_evento', 'chk_evento_desconto_pct',
    'CHECK (desconto_percentual IS NULL OR (desconto_percentual BETWEEN 0 AND 100))');
CALL adega_mig_add_constraint('tbl_evento', 'chk_evento_valores',
    'CHECK ((subtotal IS NULL OR subtotal >= 0) AND (total IS NULL OR total >= 0))');
CALL adega_mig_add_constraint('tbl_evento', 'chk_evento_total',
    'CHECK (total IS NULL OR subtotal IS NULL OR total = subtotal - desconto_valor)');
CALL adega_mig_add_constraint('tbl_evento', 'chk_evento_cancelamento',
    'CHECK (status = ''CONCLUIDA'' OR cancelado_em IS NOT NULL)');

CALL adega_mig_add_column('item_evento', 'preco_unitario', 'DECIMAL(10,2) NULL');
CALL adega_mig_add_column('item_evento', 'subtotal_item', 'DECIMAL(10,2) NULL');
CALL adega_mig_add_constraint('item_evento', 'chk_item_evento_valores',
    'CHECK ((preco_unitario IS NULL OR preco_unitario >= 0) AND (subtotal_item IS NULL OR subtotal_item >= 0))');

CREATE TABLE IF NOT EXISTS evento_pagamento (
    id_pagamento INT PRIMARY KEY AUTO_INCREMENT,
    id_evento INT NOT NULL,
    id_forma_pagamento INT NOT NULL,
    valor_recebido DECIMAL(10,2) NOT NULL,
    valor_aplicado DECIMAL(10,2) NOT NULL,
    troco DECIMAL(10,2) NOT NULL DEFAULT 0,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_evento_pagamento_evento FOREIGN KEY (id_evento) REFERENCES tbl_evento(id_evento),
    CONSTRAINT fk_evento_pagamento_forma FOREIGN KEY (id_forma_pagamento) REFERENCES dmsao_forma_pagamento(id_forma_pagamento),
    CONSTRAINT chk_evento_pagamento_valores CHECK (
        valor_aplicado >= 0 AND troco >= 0 AND valor_recebido >= valor_aplicado
        AND troco = valor_recebido - valor_aplicado)
);

CALL adega_mig_add_index('evento_pagamento', 'idx_evento_pagamento_evento', 'id_evento');
CALL adega_mig_add_index('evento_pagamento', 'idx_evento_pagamento_forma', 'id_forma_pagamento');


DELIMITER $$
DROP PROCEDURE IF EXISTS adega_mig_add_column$$
DROP PROCEDURE IF EXISTS adega_mig_add_index$$
DROP PROCEDURE IF EXISTS adega_mig_add_constraint$$
DROP PROCEDURE IF EXISTS adega_mig_add_check_if_clean$$
DROP PROCEDURE IF EXISTS adega_mig_add_unique_if_clean$$
DELIMITER ;

