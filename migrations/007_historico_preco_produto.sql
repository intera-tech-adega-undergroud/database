-- 007. Histórico de preços || Monólito (back-end)  [Step 0 / item #14]
-- - historico_preco_produto: preço anterior e novo, quem alterou, quando e a origem.
-- - tbl_produto.preco_alterado_por: "caixa de correio" para a aplicação informar o usuário no MESMO
--   UPDATE que muda o preço. A trigger (008) lê o valor, grava no histórico e zera a coluna.
-- - Foto inicial: uma linha INICIAL por produto que ainda não tem histórico.
-- ON DELETE CASCADE na FK do produto porque o back-end atual exclui produtos fisicamente
-- (ProdutoController.deletar); sem isso, excluir um produto sem vendas passaria a falhar.
-- Compatível com o back-end atual (coluna nova NULL, não mapeada). Idempotente.
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


CREATE TABLE IF NOT EXISTS historico_preco_produto (
    id_historico_preco INT PRIMARY KEY AUTO_INCREMENT,
    id_produto INT NOT NULL,
    preco_anterior DECIMAL(10,2) NULL,
    preco_novo DECIMAL(10,2) NOT NULL,
    id_funcionario INT NULL,
    alterado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    origem ENUM('INICIAL','APLICACAO','BANCO') NOT NULL DEFAULT 'BANCO',
    CONSTRAINT fk_historico_preco_produto FOREIGN KEY (id_produto) REFERENCES tbl_produto(id_produto) ON DELETE CASCADE,
    CONSTRAINT fk_historico_preco_funcionario FOREIGN KEY (id_funcionario) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT chk_historico_preco_valores CHECK (preco_novo >= 0 AND (preco_anterior IS NULL OR preco_anterior >= 0))
);

CALL adega_mig_add_index('historico_preco_produto', 'idx_historico_preco_produto_data', 'id_produto, alterado_em');
CALL adega_mig_add_index('historico_preco_produto', 'idx_historico_preco_data', 'alterado_em');

CALL adega_mig_add_column('tbl_produto', 'preco_alterado_por', 'INT NULL');
CALL adega_mig_add_constraint('tbl_produto', 'fk_produto_preco_alterado_por',
    'FOREIGN KEY (preco_alterado_por) REFERENCES tbl_funcionario(id_funcionario)');

INSERT INTO historico_preco_produto (id_produto, preco_anterior, preco_novo, id_funcionario, origem)
SELECT p.id_produto, NULL, p.preco, NULL, 'INICIAL'
FROM tbl_produto p
WHERE NOT EXISTS (SELECT 1 FROM historico_preco_produto h WHERE h.id_produto = p.id_produto);


DELIMITER $$
DROP PROCEDURE IF EXISTS adega_mig_add_column$$
DROP PROCEDURE IF EXISTS adega_mig_add_index$$
DROP PROCEDURE IF EXISTS adega_mig_add_constraint$$
DROP PROCEDURE IF EXISTS adega_mig_add_check_if_clean$$
DROP PROCEDURE IF EXISTS adega_mig_add_unique_if_clean$$
DELIMITER ;

