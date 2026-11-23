-- Cenários de aceite do Step 0 (somente leitura de resultado: tudo roda dentro de uma transação com ROLLBACK).
-- Rode num banco CRIADO PELO NOVO script_create_database.sql (ou num legado já migrado) e confira que
-- TODAS as linhas finais mostram PASS. Usa funcionários 1 a 3 e produtos 1, 9 e 10 dos dados de exemplo.
USE adega_underground;
SET NAMES utf8mb4;

DROP TEMPORARY TABLE IF EXISTS adega_t_resultado;
CREATE TEMPORARY TABLE adega_t_resultado (cenario VARCHAR(120), resultado VARCHAR(60)) ENGINE=MEMORY;

DELIMITER $$
DROP PROCEDURE IF EXISTS adega_t_igual$$
CREATE PROCEDURE adega_t_igual(IN p_nome VARCHAR(120), IN p_esperado DECIMAL(12,2), IN p_obtido DECIMAL(12,2))
BEGIN
    INSERT INTO adega_t_resultado VALUES (p_nome, IF(p_esperado <=> p_obtido, 'PASS', CONCAT('FAIL (obtido=', IFNULL(p_obtido,'NULL'), ')')));
END$$

DROP PROCEDURE IF EXISTS adega_t_rejeita$$
CREATE PROCEDURE adega_t_rejeita(IN p_nome VARCHAR(120), IN p_sql TEXT)
BEGIN
    DECLARE v_rejeitou INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_rejeitou = 1;
    SET @adega_t_sql = p_sql;
    PREPARE adega_t_stmt FROM @adega_t_sql;
    EXECUTE adega_t_stmt;
    DEALLOCATE PREPARE adega_t_stmt;
    INSERT INTO adega_t_resultado VALUES (p_nome, IF(v_rejeitou = 1, 'PASS', 'FAIL (era para ser rejeitado)'));
END$$
DELIMITER ;

START TRANSACTION;

-- ===== Caixas: dois operadores, dois caixas abertos =====
INSERT INTO caixa (id_funcionario_responsavel, fundo_inicial) VALUES (2, 100.00);
SET @caixa1 = LAST_INSERT_ID();
INSERT INTO caixa (id_funcionario_responsavel, fundo_inicial) VALUES (3, 50.00);
SET @caixa2 = LAST_INSERT_ID();

-- ===== Venda 1: R$ 18 = R$ 10 no Pix + R$ 8 em dinheiro =====
INSERT INTO tbl_evento (tipo, forma_pagamento, pago, tbl_funcionario_id_funcionario, id_funcionario_executor,
                        subtotal, desconto_valor, total, id_caixa)
VALUES ('VENDA', 'MISTO', 1, 2, 2, 18.00, 0, 18.00, @caixa1);
SET @v1 = LAST_INSERT_ID();
INSERT INTO item_evento (id_evento, id_produto, quantidade, preco_unitario, subtotal_item) VALUES
(@v1, 10, 1, 14.00, 14.00), (@v1, 9, 1, 4.00, 4.00);
INSERT INTO evento_pagamento (id_evento, id_forma_pagamento, valor_recebido, valor_aplicado, troco)
SELECT @v1, id_forma_pagamento, 10, 10, 0 FROM dmsao_forma_pagamento WHERE codigo = 'PIX';
INSERT INTO evento_pagamento (id_evento, id_forma_pagamento, valor_recebido, valor_aplicado, troco)
SELECT @v1, id_forma_pagamento, 8, 8, 0 FROM dmsao_forma_pagamento WHERE codigo = 'DINHEIRO';

CALL adega_t_igual('Pagamento dividido: soma dos pagamentos = total da venda', 18.00,
    (SELECT SUM(valor_aplicado) FROM evento_pagamento WHERE id_evento = @v1));
CALL adega_t_igual('Pagamento dividido: valor em dinheiro da venda', 8.00,
    (SELECT SUM(ep.valor_aplicado) FROM evento_pagamento ep JOIN dmsao_forma_pagamento f USING (id_forma_pagamento)
     WHERE ep.id_evento = @v1 AND f.eh_dinheiro = 1));
CALL adega_t_igual('Pagamento dividido: valor no Pix da venda', 10.00,
    (SELECT SUM(ep.valor_aplicado) FROM evento_pagamento ep JOIN dmsao_forma_pagamento f USING (id_forma_pagamento)
     WHERE ep.id_evento = @v1 AND f.codigo = 'PIX'));

-- ===== Venda 2: R$ 38 em dinheiro, cliente deu R$ 50 (troco R$ 12) =====
INSERT INTO tbl_evento (tipo, forma_pagamento, pago, tbl_funcionario_id_funcionario, id_funcionario_executor,
                        subtotal, desconto_valor, total, id_caixa)
VALUES ('VENDA', 'DINHEIRO', 1, 2, 2, 38.00, 0, 38.00, @caixa1);
SET @v2 = LAST_INSERT_ID();
INSERT INTO item_evento (id_evento, id_produto, quantidade, preco_unitario, subtotal_item) VALUES (@v2, 1, 4, 9.50, 38.00);
INSERT INTO evento_pagamento (id_evento, id_forma_pagamento, valor_recebido, valor_aplicado, troco)
SELECT @v2, id_forma_pagamento, 50, 38, 12 FROM dmsao_forma_pagamento WHERE codigo = 'DINHEIRO';

-- ===== Venda 3 no caixa do outro operador =====
INSERT INTO tbl_evento (tipo, forma_pagamento, pago, tbl_funcionario_id_funcionario, id_funcionario_executor,
                        subtotal, desconto_valor, total, id_caixa)
VALUES ('VENDA', 'PIX', 1, 3, 3, 14.00, 0, 14.00, @caixa2);
SET @v3 = LAST_INSERT_ID();
INSERT INTO item_evento (id_evento, id_produto, quantidade, preco_unitario, subtotal_item) VALUES (@v3, 10, 1, 14.00, 14.00);
INSERT INTO evento_pagamento (id_evento, id_forma_pagamento, valor_recebido, valor_aplicado, troco)
SELECT @v3, id_forma_pagamento, 14, 14, 0 FROM dmsao_forma_pagamento WHERE codigo = 'PIX';

CALL adega_t_igual('Vínculo: vendas do caixa 1 (operador 2)', 2, (SELECT COUNT(*) FROM tbl_evento WHERE id_caixa = @caixa1));
CALL adega_t_igual('Vínculo: vendas do caixa 2 (operador 3)', 1, (SELECT COUNT(*) FROM tbl_evento WHERE id_caixa = @caixa2));

-- ===== Movimentações do caixa 1 =====
INSERT INTO movimento_caixa (id_caixa, tipo, valor, motivo, id_funcionario) VALUES
(@caixa1, 'ENTRADA_ADICIONAL', 20.00, 'Reforço de troco', 1),
(@caixa1, 'SANGRIA', 30.00, 'Retirada para o cofre', 1),
(@caixa1, 'DEVOLUCAO_DINHEIRO', 5.00, 'Devolução de produto', 2);

-- esperado = 100 (fundo) + 8 + 38 (dinheiro líquido, sem o troco) + 20 - 30 - 5 = 131
CALL adega_t_igual('Caixa 1: dinheiro esperado (fundo + dinheiro líquido + entradas - sangrias - devoluções)', 131.00,
    (SELECT valor_esperado_calculado FROM vw_caixa_resumo WHERE id_caixa = @caixa1));
CALL adega_t_igual('Caixa 1: recebimentos eletrônicos separados do dinheiro', 10.00,
    (SELECT recebimentos_eletronicos FROM vw_caixa_resumo WHERE id_caixa = @caixa1));
CALL adega_t_igual('Caixa 2: dinheiro esperado (só fundo; venda foi Pix)', 50.00,
    (SELECT valor_esperado_calculado FROM vw_caixa_resumo WHERE id_caixa = @caixa2));

CALL adega_t_rejeita('Caixa: fechar sem valor contado é rejeitado',
    CONCAT('UPDATE caixa SET status=''FECHADO'', fechado_em=NOW() WHERE id_caixa=', @caixa1));
UPDATE caixa SET status = 'FECHADO', fechado_em = NOW(), id_funcionario_fechamento = 1,
                 valor_esperado = 131.00, valor_contado = 130.00, diferenca = -1.00
WHERE id_caixa = @caixa1;
CALL adega_t_igual('Caixa 1: diferença do fechamento (contado 130 x esperado 131)', -1.00,
    (SELECT diferenca_calculada FROM vw_caixa_resumo WHERE id_caixa = @caixa1));
CALL adega_t_rejeita('Caixa: sangria com valor zero é rejeitada',
    CONCAT('INSERT INTO movimento_caixa (id_caixa,tipo,valor,motivo,id_funcionario) VALUES (', @caixa2, ',''SANGRIA'',0,''x'',1)'));

-- ===== Pagamento e desconto: regras do banco =====
CALL adega_t_rejeita('Pagamento: troco incoerente (recebido 20, aplicado 8, troco 5) é rejeitado',
    CONCAT('INSERT INTO evento_pagamento (id_evento,id_forma_pagamento,valor_recebido,valor_aplicado,troco) VALUES (', @v3, ',1,20,8,5)'));
CALL adega_t_rejeita('Venda: total diferente de subtotal - desconto é rejeitado',
    'INSERT INTO tbl_evento (tipo,tbl_funcionario_id_funcionario,subtotal,desconto_valor,total) VALUES (''VENDA'',2,100,10,95)');
CALL adega_t_rejeita('Venda: desconto negativo é rejeitado',
    'INSERT INTO tbl_evento (tipo,tbl_funcionario_id_funcionario,subtotal,desconto_valor,total) VALUES (''VENDA'',2,100,-5,105)');
CALL adega_t_rejeita('Venda: cancelada sem data de cancelamento é rejeitada',
    CONCAT('UPDATE tbl_evento SET status=''CANCELADA'' WHERE id_evento=', @v3));
INSERT INTO tbl_evento (tipo, forma_pagamento, pago, tbl_funcionario_id_funcionario, id_funcionario_executor,
                        subtotal, desconto_tipo, desconto_valor, id_funcionario_desconto, total, id_caixa)
VALUES ('VENDA', 'PIX', 1, 2, 2, 100.00, 'VALOR', 10.00, 1, 90.00, @caixa2);
CALL adega_t_igual('Desconto: total = subtotal - desconto gravado com autorizador', 90.00,
    (SELECT total FROM tbl_evento WHERE id_evento = LAST_INSERT_ID() AND id_funcionario_desconto = 1));

-- ===== Histórico de preços: vendas antigas não mudam =====
UPDATE tbl_produto SET preco = 15.00, preco_alterado_por = 1 WHERE id_produto = 10;
UPDATE tbl_produto SET preco = 16.50, preco_alterado_por = 3 WHERE id_produto = 10;
UPDATE tbl_produto SET preco = 17.00 WHERE id_produto = 10;
CALL adega_t_igual('Preço: três alterações registradas (além da foto inicial)', 3,
    (SELECT COUNT(*) FROM historico_preco_produto WHERE id_produto = 10 AND origem <> 'INICIAL'));
CALL adega_t_igual('Preço: 1ª alteração guardou preço anterior 14,00 e usuário 1', 1,
    (SELECT COUNT(*) FROM historico_preco_produto WHERE id_produto = 10 AND preco_anterior = 14.00 AND preco_novo = 15.00 AND id_funcionario = 1 AND origem = 'APLICACAO'));
CALL adega_t_igual('Preço: 2ª alteração guardou usuário 3', 1,
    (SELECT COUNT(*) FROM historico_preco_produto WHERE id_produto = 10 AND preco_anterior = 15.00 AND preco_novo = 16.50 AND id_funcionario = 3));
CALL adega_t_igual('Preço: alteração sem usuário informado vira origem BANCO (usuário antigo não vaza)', 1,
    (SELECT COUNT(*) FROM historico_preco_produto WHERE id_produto = 10 AND preco_novo = 17.00 AND id_funcionario IS NULL AND origem = 'BANCO'));
CALL adega_t_igual('Preço: venda anterior mantém o preço praticado (14,00)', 14.00,
    (SELECT preco_unitario FROM item_evento WHERE id_evento = @v1 AND id_produto = 10));

-- ===== Garrafa de 1.000 ml: abrir, vender 100 ml, amostra de 30 ml =====
INSERT INTO tbl_unidade_bebida (ml_inicial, ml_atual, status, id_produto, aberta_em) VALUES (1000, 1000, 'ABERTO', 5, NOW());
SET @garrafa = LAST_INSERT_ID();
INSERT INTO movimento_volume (id_unidade_bebida, tipo, ml_delta, ml_anterior, ml_posterior, id_funcionario)
VALUES (@garrafa, 'ABERTURA', 0, 1000, 1000, 2);
UPDATE tbl_unidade_bebida SET ml_atual = 900 WHERE id_unidade_bebida = @garrafa;
INSERT INTO movimento_volume (id_unidade_bebida, tipo, ml_delta, ml_anterior, ml_posterior, id_produto_vendido, id_evento, id_funcionario)
VALUES (@garrafa, 'VENDA', -100, 1000, 900, 8, @v1, 2);
UPDATE tbl_unidade_bebida SET ml_atual = 870 WHERE id_unidade_bebida = @garrafa;
INSERT INTO movimento_volume (id_unidade_bebida, tipo, ml_delta, ml_anterior, ml_posterior, id_funcionario, motivo)
VALUES (@garrafa, 'AMOSTRA', -30, 900, 870, 2, 'Degustação para cliente');
CALL adega_t_igual('ml: saldo da garrafa após venda de 100 e amostra de 30', 870,
    (SELECT ml_atual FROM tbl_unidade_bebida WHERE id_unidade_bebida = @garrafa));
CALL adega_t_igual('ml: saída por venda identificada', -100,
    (SELECT SUM(ml_delta) FROM movimento_volume WHERE id_unidade_bebida = @garrafa AND tipo = 'VENDA'));
CALL adega_t_igual('ml: amostra identificada separadamente', -30,
    (SELECT SUM(ml_delta) FROM movimento_volume WHERE id_unidade_bebida = @garrafa AND tipo = 'AMOSTRA'));
CALL adega_t_igual('ml: saldo bate com o razão (inicial + soma das movimentações)', 870,
    (SELECT 1000 + SUM(ml_delta) FROM movimento_volume WHERE id_unidade_bebida = @garrafa));
CALL adega_t_rejeita('ml: saldo negativo é rejeitado',
    CONCAT('UPDATE tbl_unidade_bebida SET ml_atual=-1 WHERE id_unidade_bebida=', @garrafa));
CALL adega_t_rejeita('ml: saldo acima do volume inicial é rejeitado',
    CONCAT('UPDATE tbl_unidade_bebida SET ml_atual=1001 WHERE id_unidade_bebida=', @garrafa));
CALL adega_t_rejeita('ml: saída acima do disponível (870 - 900) é rejeitada no razão',
    CONCAT('INSERT INTO movimento_volume (id_unidade_bebida,tipo,ml_delta,ml_anterior,ml_posterior) VALUES (', @garrafa, ',''VENDA'',-900,870,-30)'));
CALL adega_t_rejeita('ml: venda com delta positivo é rejeitada',
    CONCAT('INSERT INTO movimento_volume (id_unidade_bebida,tipo,ml_delta,ml_anterior,ml_posterior) VALUES (', @garrafa, ',''VENDA'',10,870,880)'));
CALL adega_t_rejeita('ml: garrafa ESGOTADA com ml > 0 é rejeitada',
    CONCAT('UPDATE tbl_unidade_bebida SET status=''ESGOTADA'' WHERE id_unidade_bebida=', @garrafa));
UPDATE tbl_unidade_bebida SET ml_atual = 0, status = 'ESGOTADA', esgotada_em = NOW() WHERE id_unidade_bebida = @garrafa;
CALL adega_t_igual('ml: garrafa vazia fica ESGOTADA (não confunde com FECHADA)', 1,
    (SELECT COUNT(*) FROM tbl_unidade_bebida WHERE id_unidade_bebida = @garrafa AND status = 'ESGOTADA' AND ml_atual = 0));

-- ===== Razão de estoque =====
INSERT INTO movimento_estoque (id_produto, tipo, quantidade_delta, saldo_anterior, saldo_posterior, id_evento, id_funcionario)
VALUES (9, 'VENDA', -40, 35, -5, @v1, 2);
CALL adega_t_igual('Estoque: razão aceita saldo negativo (regra de negócio vigente)', -5,
    (SELECT saldo_posterior FROM movimento_estoque WHERE id_produto = 9 AND id_evento = @v1));
CALL adega_t_rejeita('Estoque: razão com saldo que não bate é rejeitado',
    'INSERT INTO movimento_estoque (id_produto,tipo,quantidade_delta,saldo_anterior,saldo_posterior) VALUES (9,''VENDA'',-1,10,10)');

-- ===== Funcionários =====
INSERT INTO tbl_funcionario (nome_usuario, senha_cripto, cpf, celular, email)
VALUES ('Teste Bcrypt', '$2a$10$abcdefghijklmnopqrstuvABCDEFGHIJKLMNOPQRSTUVWXYZ01234', '99988877766', '11900000000', 'teste.step0@adega.com');
CALL adega_t_igual('Funcionário: senha BCrypt de 60 caracteres cabe', 60,
    (SELECT CHAR_LENGTH(senha_cripto) FROM tbl_funcionario WHERE email = 'teste.step0@adega.com'));
CALL adega_t_rejeita('Funcionário: e-mail duplicado é rejeitado',
    'INSERT INTO tbl_funcionario (nome_usuario,senha_cripto,cpf,celular,email) VALUES (''Dup'',''x'',''11111111111'',''1'',''teste.step0@adega.com'')');
CALL adega_t_rejeita('Funcionário: CPF duplicado é rejeitado',
    'INSERT INTO tbl_funcionario (nome_usuario,senha_cripto,cpf,celular,email) VALUES (''Dup'',''x'',''99988877766'',''1'',''outro@adega.com'')');
UPDATE tbl_funcionario SET ativo = 0, desativado_em = NOW() WHERE id_funcionario = 2;
CALL adega_t_igual('Funcionário desativado: vendas dele continuam no histórico', 2,
    (SELECT COUNT(*) FROM tbl_evento WHERE tbl_funcionario_id_funcionario = 2 AND id_caixa = @caixa1));

-- ===== Permissões já nos códigos do back-end =====
CALL adega_t_igual('Permissões: nenhum rótulo antigo ("Visualizar ...") sobrou', 0,
    (SELECT COUNT(*) FROM dmsao_permissao WHERE permissao LIKE '% %'));

ROLLBACK;

SELECT cenario, resultado FROM adega_t_resultado;
SELECT IF(SUM(resultado <> 'PASS') = 0, 'TODOS OS CENÁRIOS PASSARAM', CONCAT(SUM(resultado <> 'PASS'), ' CENÁRIO(S) COM FALHA')) AS resumo
FROM adega_t_resultado;

DROP PROCEDURE IF EXISTS adega_t_igual;
DROP PROCEDURE IF EXISTS adega_t_rejeita;
DROP TEMPORARY TABLE IF EXISTS adega_t_resultado;
