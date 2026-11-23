-- 005. Preenchimento dos valores das vendas existentes || dados (re-executável)  [Step 0 / item #2]
-- Vendas antigas não guardaram o preço praticado. Aqui se usa o PREÇO ATUAL do produto como melhor
-- estimativa e a venda fica marcada com tbl_evento.valores_estimados = 1.
-- Só toca linhas ainda sem valor (preco_unitario IS NULL / subtotal IS NULL). Por isso pode e deve ser
-- executado de novo imediatamente antes de publicar o Step 2: vendas feitas pelo back-end antigo depois
-- da 004 também entram sem valor e serão preenchidas (e marcadas como estimadas).
USE adega_underground;
SET NAMES utf8mb4;

UPDATE item_evento ie
JOIN tbl_produto p ON p.id_produto = ie.id_produto
SET ie.preco_unitario = p.preco,
    ie.subtotal_item = p.preco * ie.quantidade
WHERE ie.preco_unitario IS NULL;

UPDATE tbl_evento e
JOIN (SELECT id_evento, SUM(subtotal_item) AS soma FROM item_evento GROUP BY id_evento) x
  ON x.id_evento = e.id_evento
SET e.subtotal = x.soma,
    e.total = x.soma - e.desconto_valor,
    e.valores_estimados = 1
WHERE e.tipo = 'VENDA' AND e.subtotal IS NULL;

UPDATE tbl_evento
SET id_funcionario_executor = tbl_funcionario_id_funcionario
WHERE id_funcionario_executor IS NULL;

-- Pagamentos: uma linha por venda, com a forma original normalizada. Formas não reconhecidas
-- (ex.: 'N/A' em perdas) ficam sem linha. Fiado entra como forma FIADO (não é dinheiro recebido).
INSERT INTO evento_pagamento (id_evento, id_forma_pagamento, valor_recebido, valor_aplicado, troco)
SELECT e.id_evento, f.id_forma_pagamento, e.total, e.total, 0
FROM tbl_evento e
JOIN dmsao_forma_pagamento f ON f.codigo = CASE
        WHEN e.forma_pagamento LIKE '%dinheiro%' THEN 'DINHEIRO'
        WHEN e.forma_pagamento LIKE '%pix%' THEN 'PIX'
        WHEN e.forma_pagamento LIKE '%debito%' THEN 'DEBITO'
        WHEN e.forma_pagamento LIKE '%credito%' THEN 'CREDITO'
        WHEN e.forma_pagamento LIKE '%fiado%' THEN 'FIADO'
    END
WHERE e.tipo = 'VENDA'
  AND e.total IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM evento_pagamento ep WHERE ep.id_evento = e.id_evento);
