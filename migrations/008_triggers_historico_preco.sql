-- 008. Triggers do histórico de preços || Monólito (back-end)  [Step 0 / item #14]
-- Arquivo separado de propósito: criar trigger exige o privilégio TRIGGER e, com log binário ligado
-- (ex.: RDS), também SUPER ou log_bin_trust_function_creators=1; sem isso o MySQL responde erro 1419.
-- Se o seu banco não permitir, NÃO execute este arquivo: a tabela da 007 continua valendo e a
-- aplicação grava o histórico na mesma transação do UPDATE de preço (Step 9).
--
-- trg_produto_historico_preco_bu (BEFORE UPDATE): se o preço mudou, grava preço anterior/novo e o usuário
--   informado em preco_alterado_por (origem APLICACAO; sem usuário = BANCO) e depois ZERA a coluna,
--   para um usuário antigo nunca ser atribuído a uma alteração futura.
-- trg_produto_historico_preco_ai (AFTER INSERT): foto inicial de todo produto novo.
-- Idempotente: pode ser executado mais de uma vez sem erro.
USE adega_underground;
SET NAMES utf8mb4;

DELIMITER $$

DROP TRIGGER IF EXISTS trg_produto_historico_preco_bu$$
CREATE TRIGGER trg_produto_historico_preco_bu
BEFORE UPDATE ON tbl_produto
FOR EACH ROW
BEGIN
    IF NOT (OLD.preco <=> NEW.preco) THEN
        INSERT INTO historico_preco_produto (id_produto, preco_anterior, preco_novo, id_funcionario, origem)
        VALUES (NEW.id_produto, OLD.preco, NEW.preco, NEW.preco_alterado_por,
                IF(NEW.preco_alterado_por IS NULL, 'BANCO', 'APLICACAO'));
    END IF;
    SET NEW.preco_alterado_por = NULL;
END$$

DROP TRIGGER IF EXISTS trg_produto_historico_preco_ai$$
CREATE TRIGGER trg_produto_historico_preco_ai
AFTER INSERT ON tbl_produto
FOR EACH ROW
BEGIN
    INSERT INTO historico_preco_produto (id_produto, preco_anterior, preco_novo, id_funcionario, origem)
    VALUES (NEW.id_produto, NULL, NEW.preco, NULL, 'INICIAL');
END$$

DELIMITER ;
