-- Diagnóstico ANTES de aplicar as migrations 003 a 010 no banco com dados reais (somente SELECT).
-- Roda no schema atual (antes das migrations). Cada consulta lista o que precisa de atenção;
-- resultado vazio = nada a corrigir. Não exibe senhas.
USE adega_underground;
SET NAMES utf8mb4;

SELECT '1. CPF duplicado (impede UNIQUE da 003)' AS verificacao, cpf, COUNT(*) AS qtd
FROM tbl_funcionario WHERE cpf IS NOT NULL GROUP BY cpf HAVING COUNT(*) > 1;

SELECT '2. E-mail duplicado (impede UNIQUE da 003)' AS verificacao, email, COUNT(*) AS qtd
FROM tbl_funcionario WHERE email IS NOT NULL GROUP BY email HAVING COUNT(*) > 1;

SELECT '3. Funcionário com senha em texto puro (redefinir a senha)' AS verificacao, id_funcionario, nome_usuario
FROM tbl_funcionario WHERE senha_cripto NOT LIKE '$2%';

SELECT '4. Permissão repetida (impede UNIQUE da 003)' AS verificacao, permissao, COUNT(*) AS qtd
FROM dmsao_permissao GROUP BY permissao HAVING COUNT(*) > 1;

SELECT '5. Garrafa com ml inválido (impede CHECK da 009): negativo, acima do inicial ou inicial <= 0' AS verificacao,
       id_unidade_bebida, id_produto, ml_inicial, ml_atual, status
FROM tbl_unidade_bebida
WHERE (ml_inicial IS NOT NULL AND ml_inicial <= 0)
   OR (ml_atual IS NOT NULL AND ml_atual < 0)
   OR (ml_inicial IS NOT NULL AND ml_atual IS NOT NULL AND ml_atual > ml_inicial);

SELECT '6. Garrafa ABERTA com 0 ml (passará a ser ESGOTADA no Step 5)' AS verificacao,
       id_unidade_bebida, id_produto, ml_inicial, ml_atual
FROM tbl_unidade_bebida WHERE status = 'ABERTO' AND ml_atual = 0;

SELECT '7. Mais garrafas FECHADAS rastreadas do que o saldo qtd_unidade do produto' AS verificacao,
       p.id_produto, p.nome, p.qtd_unidade, COUNT(*) AS linhas_fechadas
FROM tbl_unidade_bebida ub JOIN tbl_produto p ON p.id_produto = ub.id_produto
WHERE ub.status = 'FECHADO' AND ub.ml_atual > 0
GROUP BY p.id_produto, p.nome, p.qtd_unidade
HAVING COUNT(*) > p.qtd_unidade;

SELECT '8. Dose/drink sem produto pai ou pai sem volume (baixa de ml não funciona)' AS verificacao,
       p.id_produto, p.nome, c.categoria, p.id_produto_pai, p.volume_ml
FROM tbl_produto p JOIN dmsao_categoria c ON c.id_categoria = p.id_categoria
LEFT JOIN tbl_produto pai ON pai.id_produto = p.id_produto_pai
WHERE c.categoria IN ('BEBIDA FRACIONADA', 'DRINK')
  AND (p.id_produto_pai IS NULL OR pai.volume_ml IS NULL OR pai.volume_ml <= 0 OR p.volume_ml IS NULL OR p.volume_ml <= 0);

SELECT '9. Saldo de estoque negativo (informativo; não é zerado pelas migrations)' AS verificacao,
       id_produto, nome, qtd_unidade, qtd_minimo
FROM tbl_produto WHERE qtd_unidade < 0;

SELECT '10. Combo sem componentes cadastrados (venda falha)' AS verificacao, p.id_produto, p.nome
FROM tbl_produto p JOIN dmsao_categoria c ON c.id_categoria = p.id_categoria
WHERE c.categoria = 'COMBO'
  AND NOT EXISTS (SELECT 1 FROM tbl_combo cb WHERE cb.tbl_produto_id_combo = p.id_produto);

SELECT '11. Venda sem itens (não terá total no backfill)' AS verificacao, e.id_evento, e.data_hora_evento
FROM tbl_evento e
WHERE e.tipo = 'VENDA' AND NOT EXISTS (SELECT 1 FROM item_evento ie WHERE ie.id_evento = e.id_evento);

SELECT '12. Forma de pagamento não reconhecida em vendas (ficará sem linha em evento_pagamento)' AS verificacao,
       forma_pagamento, COUNT(*) AS qtd
FROM tbl_evento
WHERE tipo = 'VENDA'
  AND NOT (forma_pagamento LIKE '%dinheiro%' OR forma_pagamento LIKE '%pix%' OR forma_pagamento LIKE '%debito%'
           OR forma_pagamento LIKE '%credito%' OR forma_pagamento LIKE '%fiado%')
GROUP BY forma_pagamento;

SELECT '13. Produto com preço zerado ou negativo' AS verificacao, id_produto, nome, preco
FROM tbl_produto WHERE preco <= 0;

SELECT '14. Vendas que serão marcadas como valores ESTIMADOS (preço atual aplicado ao passado)' AS verificacao,
       COUNT(*) AS vendas, MIN(data_hora_evento) AS primeira, MAX(data_hora_evento) AS ultima
FROM tbl_evento WHERE tipo = 'VENDA';
