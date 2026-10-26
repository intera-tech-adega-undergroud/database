-- 002. Coluna valor_compra em tbl_produto || Monólito (back-end)
-- A entidade Produto mapeia valorCompra (Integer) e a coluna não existia no script de criação,
-- o que impede a subida do monólito com ddl-auto=validate.
-- Idempotente: só adiciona a coluna se ela ainda não existir.
USE adega_underground;

SET @coluna_existe := (
    SELECT COUNT(*)
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'tbl_produto'
      AND COLUMN_NAME = 'valor_compra'
);

SET @ddl := IF(@coluna_existe = 0,
    'ALTER TABLE tbl_produto ADD COLUMN valor_compra INT NULL AFTER qtd_unidade',
    'SELECT ''valor_compra ja existe em tbl_produto'' AS aviso');

PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
