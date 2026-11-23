-- 006. Caixa || Monólito (back-end)  [Step 0 / itens #1 e #4]
-- - caixa: abertura (fundo inicial) e fechamento (esperado, contado, diferença).
-- - movimento_caixa: entrada adicional, sangria e devolução em dinheiro, com usuário, horário e motivo.
-- - tbl_evento.id_caixa: caixa em que a venda/recebimento foi feito (NULL nas vendas antigas).
-- - vw_caixa_resumo: UMA fórmula de cálculo para histórico, fechamento e resumos:
--     esperado = fundo inicial + recebimentos líquidos em dinheiro + entradas adicionais
--                - sangrias - devoluções em dinheiro
--   "Líquido" = valor_aplicado (sem o troco). Pagamentos de vendas canceladas continuam somados;
--   o estorno em dinheiro entra como DEVOLUCAO_DINHEIRO (evita subtrair duas vezes).
-- Modelo de caixa (separado/compartilhado/revezamento) ainda não definido: o banco NÃO impõe
-- "um caixa aberto por operador"; essa regra fica no serviço (Step 4).
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


CREATE TABLE IF NOT EXISTS caixa (
    id_caixa INT PRIMARY KEY AUTO_INCREMENT,
    id_funcionario_responsavel INT NOT NULL,
    aberto_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fundo_inicial DECIMAL(10,2) NOT NULL DEFAULT 0,
    status ENUM('ABERTO','FECHADO') NOT NULL DEFAULT 'ABERTO',
    fechado_em DATETIME NULL,
    id_funcionario_fechamento INT NULL,
    valor_esperado DECIMAL(10,2) NULL,
    valor_contado DECIMAL(10,2) NULL,
    diferenca DECIMAL(10,2) NULL,
    observacao VARCHAR(255) NULL,
    CONSTRAINT fk_caixa_responsavel FOREIGN KEY (id_funcionario_responsavel) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT fk_caixa_fechamento FOREIGN KEY (id_funcionario_fechamento) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT chk_caixa_fundo CHECK (fundo_inicial >= 0),
    CONSTRAINT chk_caixa_fechamento CHECK (
        status = 'ABERTO' OR (fechado_em IS NOT NULL AND valor_contado IS NOT NULL AND id_funcionario_fechamento IS NOT NULL))
);

CALL adega_mig_add_index('caixa', 'idx_caixa_status', 'status, aberto_em');
CALL adega_mig_add_index('caixa', 'idx_caixa_responsavel', 'id_funcionario_responsavel, status');

CREATE TABLE IF NOT EXISTS movimento_caixa (
    id_movimento_caixa INT PRIMARY KEY AUTO_INCREMENT,
    id_caixa INT NOT NULL,
    tipo ENUM('ENTRADA_ADICIONAL','SANGRIA','DEVOLUCAO_DINHEIRO') NOT NULL,
    valor DECIMAL(10,2) NOT NULL,
    motivo VARCHAR(255) NOT NULL,
    id_funcionario INT NOT NULL,
    id_evento INT NULL,
    criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_movimento_caixa_caixa FOREIGN KEY (id_caixa) REFERENCES caixa(id_caixa),
    CONSTRAINT fk_movimento_caixa_funcionario FOREIGN KEY (id_funcionario) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT fk_movimento_caixa_evento FOREIGN KEY (id_evento) REFERENCES tbl_evento(id_evento),
    CONSTRAINT chk_movimento_caixa_valor CHECK (valor > 0)
);

CALL adega_mig_add_index('movimento_caixa', 'idx_movimento_caixa_caixa', 'id_caixa, criado_em');

CALL adega_mig_add_column('tbl_evento', 'id_caixa', 'INT NULL');
CALL adega_mig_add_constraint('tbl_evento', 'fk_evento_caixa', 'FOREIGN KEY (id_caixa) REFERENCES caixa(id_caixa)');

CREATE OR REPLACE VIEW vw_caixa_resumo AS
SELECT t.*,
       t.valor_contado - t.valor_esperado_calculado AS diferenca_calculada
FROM (
    SELECT c.id_caixa,
           c.id_funcionario_responsavel,
           c.status,
           c.aberto_em,
           c.fechado_em,
           c.fundo_inicial,
           COALESCE(r.dinheiro, 0)   AS recebimentos_dinheiro,
           COALESCE(r.eletronico, 0) AS recebimentos_eletronicos,
           COALESCE(m.entradas, 0)   AS entradas_adicionais,
           COALESCE(m.sangrias, 0)   AS sangrias,
           COALESCE(m.devolucoes, 0) AS devolucoes_dinheiro,
           c.fundo_inicial + COALESCE(r.dinheiro, 0) + COALESCE(m.entradas, 0)
               - COALESCE(m.sangrias, 0) - COALESCE(m.devolucoes, 0) AS valor_esperado_calculado,
           c.valor_contado
    FROM caixa c
    LEFT JOIN (
        SELECT e.id_caixa,
               SUM(IF(f.eh_dinheiro = 1, ep.valor_aplicado, 0)) AS dinheiro,
               SUM(IF(f.eh_dinheiro = 0 AND f.gera_saldo_devedor = 0, ep.valor_aplicado, 0)) AS eletronico
        FROM tbl_evento e
        JOIN evento_pagamento ep ON ep.id_evento = e.id_evento
        JOIN dmsao_forma_pagamento f ON f.id_forma_pagamento = ep.id_forma_pagamento
        WHERE e.id_caixa IS NOT NULL
        GROUP BY e.id_caixa
    ) r ON r.id_caixa = c.id_caixa
    LEFT JOIN (
        SELECT id_caixa,
               SUM(IF(tipo = 'ENTRADA_ADICIONAL', valor, 0)) AS entradas,
               SUM(IF(tipo = 'SANGRIA', valor, 0)) AS sangrias,
               SUM(IF(tipo = 'DEVOLUCAO_DINHEIRO', valor, 0)) AS devolucoes
        FROM movimento_caixa
        GROUP BY id_caixa
    ) m ON m.id_caixa = c.id_caixa
) t;


DELIMITER $$
DROP PROCEDURE IF EXISTS adega_mig_add_column$$
DROP PROCEDURE IF EXISTS adega_mig_add_index$$
DROP PROCEDURE IF EXISTS adega_mig_add_constraint$$
DROP PROCEDURE IF EXISTS adega_mig_add_check_if_clean$$
DROP PROCEDURE IF EXISTS adega_mig_add_unique_if_clean$$
DELIMITER ;

