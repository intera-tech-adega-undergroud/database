-- 003. Funcionários e permissões || Monólito (back-end)  [Step 0 / itens #6 e #22]
-- - tbl_funcionario.senha_cripto cabia 45 caracteres e o BCrypt tem 60: cadastro quebrava em banco novo.
-- - Adiciona ativo/desativado_em (desativar sem perder histórico) e pin_hash (PIN de ações sensíveis, uso futuro).
-- - E-mail e CPF únicos (só se não houver duplicados hoje; veja validacao/diagnostico_pre_migracao.sql).
-- - Converte os rótulos antigos de dmsao_permissao ("Visualizar usuários") nos códigos usados pelo
--   código Java (usuarios_ver), mesclando com os códigos que o PermissaoInitializer já tenha criado.
-- Compatível com o back-end atual: só colunas novas com DEFAULT/NULL; senha_cripto continua VARCHAR.
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


ALTER TABLE tbl_funcionario MODIFY COLUMN senha_cripto VARCHAR(255) NOT NULL;
ALTER TABLE tbl_funcionario MODIFY COLUMN email VARCHAR(120) NULL;

CALL adega_mig_add_column('tbl_funcionario', 'ativo', 'TINYINT(1) NOT NULL DEFAULT 1');
CALL adega_mig_add_column('tbl_funcionario', 'desativado_em', 'DATETIME NULL');
CALL adega_mig_add_column('tbl_funcionario', 'pin_hash', 'VARCHAR(255) NULL');

CALL adega_mig_add_unique_if_clean('tbl_funcionario', 'uq_funcionario_email', 'email');
CALL adega_mig_add_unique_if_clean('tbl_funcionario', 'uq_funcionario_cpf', 'cpf');

-- Rótulo antigo -> código atual (PermissaoCodigo.java)
DROP TEMPORARY TABLE IF EXISTS adega_mig_perm_map;
CREATE TEMPORARY TABLE adega_mig_perm_map (
    rotulo VARCHAR(45) NOT NULL,
    codigo VARCHAR(45) NOT NULL
) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

INSERT INTO adega_mig_perm_map (rotulo, codigo) VALUES
('Visualizar usuários', 'usuarios_ver'),
('Cadastrar usuários', 'usuarios_criar'),
('Editar usuários', 'usuarios_editar'),
('Desativar / ativar usuários', 'usuarios_desativar'),
('Redefinir senha', 'usuarios_reset'),
('Visualizar produtos', 'produtos_ver'),
('Cadastrar produtos', 'produtos_criar'),
('Excluir / inativar produtos', 'produtos_excluir'),
('Visualizar estoque', 'estoque_ver'),
('Entrada / recebimento', 'estoque_entrada'),
('Ajuste manual', 'estoque_ajuste'),
('Perdas / quebras', 'estoque_perdas'),
('Histórico de movimentações', 'estoque_historico'),
('Registrar venda', 'vendas_registrar'),
('Aplicar desconto', 'vendas_desconto'),
('Cancelar venda', 'vendas_cancelar'),
('Histórico de vendas', 'vendas_historico');

-- 1) Onde o código já existe: repassa os vínculos do rótulo para o código e apaga o rótulo.
INSERT IGNORE INTO permissao_funcionario (tbl_funcionario_id_funcionario, dmsao_permissao_id_permissao)
SELECT pf.tbl_funcionario_id_funcionario, pn.id_permissao
FROM permissao_funcionario pf
JOIN dmsao_permissao po ON po.id_permissao = pf.dmsao_permissao_id_permissao
JOIN adega_mig_perm_map m ON m.rotulo = po.permissao
JOIN dmsao_permissao pn ON pn.permissao = m.codigo AND pn.id_permissao <> po.id_permissao;

DELETE pf FROM permissao_funcionario pf
JOIN dmsao_permissao po ON po.id_permissao = pf.dmsao_permissao_id_permissao
JOIN adega_mig_perm_map m ON m.rotulo = po.permissao
JOIN dmsao_permissao pn ON pn.permissao = m.codigo AND pn.id_permissao <> po.id_permissao;

DELETE po FROM dmsao_permissao po
JOIN adega_mig_perm_map m ON m.rotulo = po.permissao
JOIN dmsao_permissao pn ON pn.permissao = m.codigo AND pn.id_permissao <> po.id_permissao;

-- 2) Onde só existe o rótulo: renomeia para o código (mantém id e vínculos).
UPDATE dmsao_permissao po
JOIN adega_mig_perm_map m ON m.rotulo = po.permissao
SET po.permissao = m.codigo;

DROP TEMPORARY TABLE IF EXISTS adega_mig_perm_map;

CALL adega_mig_add_unique_if_clean('dmsao_permissao', 'uq_permissao_codigo', 'permissao');


DELIMITER $$
DROP PROCEDURE IF EXISTS adega_mig_add_column$$
DROP PROCEDURE IF EXISTS adega_mig_add_index$$
DROP PROCEDURE IF EXISTS adega_mig_add_constraint$$
DROP PROCEDURE IF EXISTS adega_mig_add_check_if_clean$$
DROP PROCEDURE IF EXISTS adega_mig_add_unique_if_clean$$
DELIMITER ;

