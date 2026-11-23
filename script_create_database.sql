DROP DATABASE IF EXISTS adega_underground;
CREATE DATABASE adega_underground;
USE adega_underground;
SET NAMES utf8mb4;

-- 1. Tabela de Categorias
CREATE TABLE dmsao_categoria (
    id_categoria INT PRIMARY KEY AUTO_INCREMENT,
    categoria ENUM('BEBIDA UNIDADE', 'BEBIDA FRACIONADA', 'DIVERSOS', 'DRINK', 'COMBO') NOT NULL
);

-- 2. Tabela de Funcionários
CREATE TABLE tbl_funcionario (
    id_funcionario INT PRIMARY KEY AUTO_INCREMENT,
    nome_usuario VARCHAR(45) NOT NULL,
    senha_cripto VARCHAR(255) NOT NULL,
    cpf VARCHAR(11),
    celular VARCHAR(45),
    email VARCHAR(120),
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    desativado_em DATETIME NULL,
    pin_hash VARCHAR(255) NULL,
    CONSTRAINT uq_funcionario_email UNIQUE (email),
    CONSTRAINT uq_funcionario_cpf UNIQUE (cpf)
);

-- 3. Tabela de Clientes
CREATE TABLE tbl_cliente (
    id_cliente INT PRIMARY KEY AUTO_INCREMENT,
    compra_fiado TINYINT(1) DEFAULT 0,
    nome VARCHAR(45) NOT NULL,
    email VARCHAR(45),
    telefone VARCHAR(45),
    saldo_devedor DECIMAL(10,2) DEFAULT 0.00
);

-- 4. Tabela de Produtos
CREATE TABLE tbl_produto (
    id_produto INT PRIMARY KEY AUTO_INCREMENT,
    nome VARCHAR(45) NOT NULL,
    preco DECIMAL(7,2) NOT NULL,
    ativo TINYINT(1) DEFAULT 1,
    embalagem ENUM('N/D', 'GARRAFA', 'LATA') DEFAULT 'N/D',
    volume_ml INT,
    id_categoria INT,
    imagem VARCHAR(255),
    qtd_minimo INT DEFAULT 0,
    qtd_unidade INT DEFAULT 0,
    valor_compra INT NULL,

    id_produto_pai INT NULL,
    custo_unitario DECIMAL(10,2) NULL,
    versao INT NOT NULL DEFAULT 0,
    preco_alterado_por INT NULL,

    CONSTRAINT fk_produto_preco_alterado_por
        FOREIGN KEY (preco_alterado_por)
        REFERENCES tbl_funcionario(id_funcionario),

    CONSTRAINT chk_produto_custo
        CHECK (custo_unitario IS NULL OR custo_unitario >= 0),

    CONSTRAINT fk_produto_categoria
        FOREIGN KEY (id_categoria)
        REFERENCES dmsao_categoria(id_categoria),

    CONSTRAINT fk_produto_pai
        FOREIGN KEY (id_produto_pai)
        REFERENCES tbl_produto(id_produto)
);

-- 5. Tabela de Eventos (Vendas/Movimentações)
CREATE TABLE tbl_evento (
    id_evento INT PRIMARY KEY AUTO_INCREMENT,
    tipo ENUM('VENDA', 'PERDA', 'RECEBIMENTO') NOT NULL,
    data_hora_evento DATETIME DEFAULT CURRENT_TIMESTAMP,
    descricao VARCHAR(255),
    forma_pagamento VARCHAR(45),
    pago TINYINT(1) DEFAULT 0,
    tbl_cliente_id_cliente INT,
    tbl_funcionario_id_funcionario INT NOT NULL,
    id_funcionario_executor INT NULL,
    subtotal DECIMAL(10,2) NULL,
    desconto_tipo ENUM('VALOR','PERCENTUAL') NULL,
    desconto_percentual DECIMAL(5,2) NULL,
    desconto_valor DECIMAL(10,2) NOT NULL DEFAULT 0,
    id_funcionario_desconto INT NULL,
    total DECIMAL(10,2) NULL,
    status ENUM('CONCLUIDA','CANCELADA') NOT NULL DEFAULT 'CONCLUIDA',
    cancelado_em DATETIME NULL,
    id_funcionario_cancelamento INT NULL,
    motivo_cancelamento VARCHAR(255) NULL,
    valores_estimados TINYINT(1) NOT NULL DEFAULT 0,
    id_caixa INT NULL,
    CONSTRAINT fk_evento_cliente FOREIGN KEY (tbl_cliente_id_cliente) REFERENCES tbl_cliente(id_cliente),
    CONSTRAINT fk_evento_funcionario FOREIGN KEY (tbl_funcionario_id_funcionario) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT fk_evento_executor FOREIGN KEY (id_funcionario_executor) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT fk_evento_func_desconto FOREIGN KEY (id_funcionario_desconto) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT fk_evento_func_cancelamento FOREIGN KEY (id_funcionario_cancelamento) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT chk_evento_desconto_valor CHECK (desconto_valor >= 0),
    CONSTRAINT chk_evento_desconto_pct CHECK (desconto_percentual IS NULL OR (desconto_percentual BETWEEN 0 AND 100)),
    CONSTRAINT chk_evento_valores CHECK ((subtotal IS NULL OR subtotal >= 0) AND (total IS NULL OR total >= 0)),
    CONSTRAINT chk_evento_total CHECK (total IS NULL OR subtotal IS NULL OR total = subtotal - desconto_valor),
    CONSTRAINT chk_evento_cancelamento CHECK (status = 'CONCLUIDA' OR cancelado_em IS NOT NULL),
    INDEX idx_evento_tipo_status_data (tipo, status, data_hora_evento),
    INDEX idx_evento_data (data_hora_evento),
    INDEX idx_evento_caixa (id_caixa),
    INDEX idx_evento_funcionario_data (tbl_funcionario_id_funcionario, data_hora_evento)
);

-- 6. Tabela de Itens do Evento (Relacionamento N:M entre Evento e Produto)
CREATE TABLE item_evento (
    id_evento INT NOT NULL,
    id_produto INT NOT NULL,
    quantidade INT NOT NULL,
    preco_unitario DECIMAL(10,2) NULL,
    subtotal_item DECIMAL(10,2) NULL,
    PRIMARY KEY (id_evento, id_produto),
    CONSTRAINT fk_item_evento FOREIGN KEY (id_evento) REFERENCES tbl_evento(id_evento),
    CONSTRAINT fk_item_produto FOREIGN KEY (id_produto) REFERENCES tbl_produto(id_produto),
    CONSTRAINT chk_item_evento_valores CHECK ((preco_unitario IS NULL OR preco_unitario >= 0) AND (subtotal_item IS NULL OR subtotal_item >= 0))
);

-- 7. Tabela de Combos (Auto-relacionamento ou Composição)
CREATE TABLE tbl_combo (
    tbl_produto_id_combo INT NOT NULL,
    tbl_produto_id_produto INT NOT NULL,
    quantidade_produto INT NOT NULL,
    PRIMARY KEY (tbl_produto_id_combo, tbl_produto_id_produto),
    CONSTRAINT fk_combo_principal FOREIGN KEY (tbl_produto_id_combo) REFERENCES tbl_produto(id_produto),
    CONSTRAINT fk_combo_item FOREIGN KEY (tbl_produto_id_produto) REFERENCES tbl_produto(id_produto)
);

-- 8. Tabela de Unidade de Bebida (Controle de Fracionados)
CREATE TABLE tbl_unidade_bebida (
    id_unidade_bebida INT PRIMARY KEY AUTO_INCREMENT,
    ml_inicial INT,
    ml_atual INT,
    status ENUM('ABERTO', 'FECHADO', 'ESGOTADA') DEFAULT 'FECHADO',
    id_produto INT NOT NULL,
    versao INT NOT NULL DEFAULT 0,
    aberta_em DATETIME NULL,
    esgotada_em DATETIME NULL,
    CONSTRAINT fk_unidade_produto FOREIGN KEY (id_produto) REFERENCES tbl_produto(id_produto),
    CONSTRAINT chk_unidade_volume CHECK (
        (ml_inicial IS NULL OR ml_inicial > 0) AND (ml_atual IS NULL OR ml_atual >= 0)
        AND (ml_inicial IS NULL OR ml_atual IS NULL OR ml_atual <= ml_inicial)),
    CONSTRAINT chk_unidade_esgotada CHECK (status <> 'ESGOTADA' OR ml_atual = 0)
);

-- 9. Tabela de Logs
CREATE TABLE log (
    idlog INT PRIMARY KEY AUTO_INCREMENT,
    descricao TEXT,
    tipo ENUM('ERRO', 'ACONTECIMENTO') NOT NULL,
    data_hora DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 10. Dimensão para permissões
CREATE TABLE dmsao_permissao (
    id_permissao INT PRIMARY KEY AUTO_INCREMENT,
    permissao VARCHAR(45) NOT NULL,
    CONSTRAINT uq_permissao_codigo UNIQUE (permissao)
);

-- 11. Tabela de permissões de funcionarios
CREATE TABLE permissao_funcionario (
    tbl_funcionario_id_funcionario INT,
    dmsao_permissao_id_permissao INT,
    PRIMARY KEY (
        tbl_funcionario_id_funcionario,
        dmsao_permissao_id_permissao
    ),
    CONSTRAINT fk_permissao_funcionario_funcionario
        FOREIGN KEY (tbl_funcionario_id_funcionario)
        REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT fk_permissao_funcionario_permissao
        FOREIGN KEY (dmsao_permissao_id_permissao)
        REFERENCES dmsao_permissao(id_permissao)
);

-- 12. Tabela de daily-report || Micro-serviço
CREATE TABLE daily_report_processed (
    reference_date DATE PRIMARY KEY,
    processed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- 13. Tabela de alertas de estoque enviados || Micro-serviço (notification-service)
-- Trava + registro: no máximo 1 alerta por produto por dia (America/Sao_Paulo).
-- Sem FK para tbl_produto (desacoplamento do monólito).
CREATE TABLE notification_stock_alert_sent (
    product_id INT NOT NULL,
    reference_date DATE NOT NULL,
    event_id CHAR(36) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (product_id, reference_date),
    CONSTRAINT chk_stock_alert_sent_severity
        CHECK (severity IN ('CRITICAL', 'HIGH', 'MEDIUM'))
);


-- 14. Dimensão de formas de pagamento (normaliza dinheiro x eletrônico x fiado)
CREATE TABLE dmsao_forma_pagamento (
    id_forma_pagamento INT PRIMARY KEY AUTO_INCREMENT,
    codigo VARCHAR(20) NOT NULL,
    descricao VARCHAR(45) NOT NULL,
    eh_dinheiro TINYINT(1) NOT NULL DEFAULT 0,
    gera_saldo_devedor TINYINT(1) NOT NULL DEFAULT 0,
    ativo TINYINT(1) NOT NULL DEFAULT 1,
    CONSTRAINT uq_forma_pagamento_codigo UNIQUE (codigo)
);

INSERT INTO dmsao_forma_pagamento (codigo, descricao, eh_dinheiro, gera_saldo_devedor) VALUES
('DINHEIRO', 'Dinheiro', 1, 0),
('PIX', 'Pix', 0, 0),
('DEBITO', 'Cartão de Débito', 0, 0),
('CREDITO', 'Cartão de Crédito', 0, 0),
('FIADO', 'Fiado', 0, 1);

-- 15. Pagamentos do evento (pagamento dividido: N formas por venda; também recebimento de fiado)
CREATE TABLE evento_pagamento (
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
        AND troco = valor_recebido - valor_aplicado),
    INDEX idx_evento_pagamento_evento (id_evento),
    INDEX idx_evento_pagamento_forma (id_forma_pagamento)
);

-- 16. Caixa (abertura com fundo inicial, fechamento com esperado x contado)
CREATE TABLE caixa (
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
        status = 'ABERTO' OR (fechado_em IS NOT NULL AND valor_contado IS NOT NULL AND id_funcionario_fechamento IS NOT NULL)),
    INDEX idx_caixa_status (status, aberto_em),
    INDEX idx_caixa_responsavel (id_funcionario_responsavel, status)
);

ALTER TABLE tbl_evento
    ADD CONSTRAINT fk_evento_caixa FOREIGN KEY (id_caixa) REFERENCES caixa(id_caixa);

-- 17. Movimentações do caixa (entrada adicional, sangria, devolução em dinheiro)
CREATE TABLE movimento_caixa (
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
    CONSTRAINT chk_movimento_caixa_valor CHECK (valor > 0),
    INDEX idx_movimento_caixa_caixa (id_caixa, criado_em)
);

-- 18. Histórico de preços (alimentado pelas triggers da seção 22)
CREATE TABLE historico_preco_produto (
    id_historico_preco INT PRIMARY KEY AUTO_INCREMENT,
    id_produto INT NOT NULL,
    preco_anterior DECIMAL(10,2) NULL,
    preco_novo DECIMAL(10,2) NOT NULL,
    id_funcionario INT NULL,
    alterado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    origem ENUM('INICIAL','APLICACAO','BANCO') NOT NULL DEFAULT 'BANCO',
    CONSTRAINT fk_historico_preco_produto FOREIGN KEY (id_produto) REFERENCES tbl_produto(id_produto) ON DELETE CASCADE,
    CONSTRAINT fk_historico_preco_funcionario FOREIGN KEY (id_funcionario) REFERENCES tbl_funcionario(id_funcionario),
    CONSTRAINT chk_historico_preco_valores CHECK (preco_novo >= 0 AND (preco_anterior IS NULL OR preco_anterior >= 0)),
    INDEX idx_historico_preco_produto_data (id_produto, alterado_em),
    INDEX idx_historico_preco_data (alterado_em)
);

-- 19. Movimentação de volume (ml) por garrafa: venda, amostra, perda, ajuste, abertura
CREATE TABLE movimento_volume (
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
        OR tipo = 'AJUSTE'),
    INDEX idx_movimento_volume_unidade (id_unidade_bebida, criado_em),
    INDEX idx_movimento_volume_evento (id_evento)
);

-- 20. Movimentação de estoque em unidades (razão do estoque; saldo pode ser negativo)
CREATE TABLE movimento_estoque (
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
    CONSTRAINT chk_movimento_estoque_saldo CHECK (saldo_posterior = saldo_anterior + quantidade_delta),
    INDEX idx_movimento_estoque_produto (id_produto, criado_em),
    INDEX idx_movimento_estoque_evento (id_evento)
);

-- 21. Resumo do caixa: mesma fórmula para fechamento, histórico e resumos
-- esperado = fundo inicial + recebimentos líquidos em dinheiro + entradas adicionais - sangrias - devoluções em dinheiro
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

-- 22. Triggers do histórico de preços (exigem privilégio TRIGGER; com binlog ligado veja migrations/008)
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


-- INSERSTS
INSERT INTO dmsao_permissao (permissao) VALUES
('usuarios_ver'),
('usuarios_criar'),
('usuarios_editar'),
('usuarios_desativar'),
('usuarios_reset'),

('produtos_ver'),
('produtos_criar'),
('produtos_excluir'),

('estoque_ver'),
('estoque_entrada'),
('estoque_ajuste'),
('estoque_perdas'),
('estoque_historico'),

('vendas_registrar'),
('vendas_desconto'),
('vendas_cancelar'),
('vendas_historico');

-- =========================================================================
-- 1. CATEGORIAS (dmsao_categoria)
-- =========================================================================
INSERT INTO dmsao_categoria (categoria) VALUES 
('BEBIDA UNIDADE'), 
('BEBIDA FRACIONADA'), 
('DIVERSOS'), 
('DRINK'), 
('COMBO');

-- =========================================================================
-- 2. FUNCIONÁRIOS (tbl_funcionario)
-- =========================================================================
INSERT INTO tbl_funcionario (nome_usuario, senha_cripto, cpf, celular, email) VALUES 
('admin', '$2b$10$i41FfYzbosF1rp.y9/L9ReOw.75D4LtP8RvEt.OcRRb1ytMryTAf6', '11122233344', '11999998888', 'gerente@gmail.com'),
('caixa_lucas', '$2b$10$6v8xQKDMsrI4A9x7e6Ga0eyGDSCToewV5STeEYvuIfuaqJdeYq7R2', '22233344455', '11988887777', 'lucas.caixa@adegaunderground.com'),
('barman_igor', '$2b$10$Sm7y7uVJguqsJcaw26EKnuzZcUA//JhgLRdh26ZKEN6TOjlSQBVO.', '33344455566', '11977776666', 'igor.drinks@adegaunderground.com');

-- =========================================================================
-- 3. CLIENTES (tbl_cliente)
-- =========================================================================
INSERT INTO tbl_cliente (compra_fiado, nome, email, telefone, saldo_devedor) VALUES 
(0, 'Cliente Balcão / Não Identificado', NULL, '00000000000', 0.00),
(1, 'Carlos Silva (Carlinhos)', 'carlinhos.silva@email.com', '11966665555', 150.00),
(1, 'Mariana Oliveira', 'mari.oli@email.com', '11955554444', 0.00),
(0, 'Marcos Souza', 'marcos.souza@email.com', '11944443333', 0.00);

-- =========================================================================
-- 4. PRODUTOS (tbl_produto)
-- =========================================================================
-- Categorias: 1=Bebida Unidade, 2=Bebida Fracionada, 3=Diversos, 4=Drink, 5=Combo
INSERT INTO tbl_produto
(nome, preco, ativo, embalagem, volume_ml, id_categoria, imagem, qtd_minimo, qtd_unidade, id_produto_pai)
VALUES
('Cerveja Heineken Long Neck', 9.50, 1, 'GARRAFA', 330, 1, 'heineken_ln.png', 50, 120, NULL),
('Cerveja Amstel Latão', 6.00, 1, 'LATA', 473, 1, 'amstel_latao.png', 40, 85, NULL),
('Refrigerante Coca-Cola Lata', 5.00, 1, 'LATA', 350, 1, 'coca_lata.png', 30, 60, NULL),
('Vodka Smirnoff 998ml', 45.00, 1, 'GARRAFA', 998, 1, 'smirnoff_garrafa.png', 10, 15, NULL),
('Whisky Red Label 1L', 110.00, 1, 'GARRAFA', 1000, 1, 'red_label.png', 5, 8, NULL),
('Energético Monster 473ml', 12.00, 1, 'LATA', 473, 1, 'monster_lata.png', 20, 45, NULL),

-- Bebidas Fracionadas (Doses base para controle de estoque)
('Dose Vodka Smirnoff', 8.00, 1, 'N/D', 50, 2, 'dose_smirnoff.png', 0, 0, 4),
('Dose Whisky Red Label', 15.00, 1, 'N/D', 50, 2, 'dose_redlabel.png', 0, 0, 5),

-- Diversos
('Gelo de Coco Copão', 4.00, 1, 'N/D', NULL, 3, 'gelo_coco.png', 15, 35, NULL),
('Batata Pringles Original', 14.00, 1, 'N/D', NULL, 3, 'pringles.png', 10, 22, NULL),

-- Drinks preparados
('Copão de Cavalo de Troia', 25.00, 1, 'N/D', 200, 4, 'copao_cavalo.png', 0, 0, 4),

-- Combos (O produto "Combo" possui um preço cheio)
('Combo Red Label + 5 Monster + Gelo', 160.00, 1, 'N/D', 250, 5, 'combo_red_monster.png', 0, 0, 5);

-- =========================================================================
-- 5. EVENTOS / MOVIMENTAÇÕES (tbl_evento)
-- =========================================================================
INSERT INTO tbl_evento (id_evento, tipo, data_hora_evento, descricao, forma_pagamento, pago, tbl_cliente_id_cliente, tbl_funcionario_id_funcionario) VALUES 
-- Venda comum no balcão em dinheiro (Pago)
(1, 'VENDA', '2026-05-20 19:30:00', 'Venda rápida de cervejas', 'DINHEIRO', 1, 1, 2),

-- Venda de fiado registrada para o cliente Carlos (Não paga - aumenta saldo devedor)
(2, 'VENDA', '2026-05-20 21:15:00', 'Venda pendente - autorizado pendurar', 'FIADO', 0, 2, 2),

-- Perda de estoque (Garrafa quebrada pelo funcionário)
(3, 'PERDA', '2026-05-21 15:00:00', 'Garrafa de Vodka quebrada ao repor freezer', 'N/A', 0, NULL, 2),

-- Venda de um Combo completo no Pix
(4, 'VENDA', '2026-05-22 23:45:00', 'Combo para o camarote', 'PIX', 1, 4, 3),

-- Recebimento de dívida (Cliente Mariana pagando conta antiga)
(5, 'RECEBIMENTO', '2026-05-23 18:00:00', 'Pagamento parcial de saldo devedor anterior', 'DEBITO', 1, 3, 2),

-- Venda de drinks e fracionados
(6, 'VENDA', '2026-05-24 01:20:00', 'Pedido de doses no balcão', 'CREDITO', 1, 1, 3),

-- Venda
(7, 'VENDA', '2026-05-25 19:30:00', 'Venda rápida de cervejas', 'DINHEIRO', 1, 1, 2),

-- Venda Hoje
(8, 'VENDA', '2026-06-05 19:30:00', 'Venda rápida de cervejas', 'DINHEIRO', 1, 1, 2);

-- =========================================================================
-- 6. ITENS DO EVENTO (item_evento)
-- =========================================================================
INSERT INTO item_evento (id_evento, id_produto, quantidade) VALUES 
-- Itens do Evento 1 (Venda balcão): 4 Heineken e 1 Pringles
(1, 1, 4), 
(1, 10, 1),

-- Itens do Evento 2 (Fiado do Carlos): 1 Whisky Red Label (Inteiro)
(2, 5, 1),

-- Itens do Evento 3 (Perda): 1 Vodka Smirnoff Garrafa
(3, 4, 1),

-- Itens do Evento 4 (Venda Combo): 1 Unidade do Combo cadastrado
(4, 12, 1),

-- Itens do Evento 6 (Doses e Drinks): 2 Doses Whisky e 2 Gelos de coco
(6, 8, 2),
(6, 9, 2),

(7, 8, 2),
(7, 9, 2),

(8, 8, 2),
(8, 9, 2);

-- =========================================================================
-- 7. COMPOSIÇÃO DOS COMBOS (tbl_combo)
-- =========================================================================
-- Associa o produto ID 12 (Combo Red Label) aos itens reais que saem do estoque
INSERT INTO tbl_combo (tbl_produto_id_combo, tbl_produto_id_produto, quantidade_produto) VALUES 
(12, 5, 1),  -- 1 Whisky Red Label 1L
(12, 6, 5),  -- 5 Energéticos Monster
(12, 9, 1);  -- 1 Gelo de coco

-- =========================================================================
-- 8. UNIDADE DE BEBIDA FRACIONADA (tbl_unidade_bebida)
-- =========================================================================
-- Controla garrafas abertas no bar para servir doses (Produto 4 = Vodka, Produto 5 = Whisky)
INSERT INTO tbl_unidade_bebida (ml_inicial, ml_atual, status, id_produto) VALUES 
('998', 498, 'ABERTO', 4),  -- Uma garrafa de Vodka aberta com 498ml restantes
('1000', 0, 'ABERTO', 5),   -- Uma garrafa de Whisky que acabou de esvaziar (0ml)
('1000', 1000, 'FECHADO', 5); -- Uma garrafa de Whisky reserva deixada no balcão fechada

-- =========================================================================
-- 9. VALORES DAS VENDAS DE EXEMPLO (preço praticado, total e pagamentos)
-- =========================================================================
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

SELEcT * FROM tbl_funcionario;

-- GRAFICO Visao Detalhada de Vendas Diarias (usa o total gravado na venda, nunca o preço atual do produto)
SELECT
    DAY(e.data_hora_evento) AS dia,
    SUM(e.total) AS valor_total_vendas
FROM tbl_evento e
WHERE e.tipo = 'VENDA'
    AND e.status = 'CONCLUIDA'
    AND MONTH(e.data_hora_evento) = MONTH(CURDATE())
    AND YEAR(e.data_hora_evento) = YEAR(CURDATE())
GROUP BY DAY(e.data_hora_evento)
ORDER BY dia;

-- RANKING POR VENDEDOR
SELECT
    f.id_funcionario,
    f.nome_usuario AS vendedor,
    COUNT(*) AS quantidade_vendas,
    SUM(e.total) AS valor_total_vendido
FROM tbl_funcionario f
INNER JOIN tbl_evento e
    ON f.id_funcionario = e.tbl_funcionario_id_funcionario
WHERE e.tipo = 'VENDA'
    AND e.status = 'CONCLUIDA'
    AND MONTH(e.data_hora_evento) = MONTH(CURDATE())
    AND YEAR(e.data_hora_evento) = YEAR(CURDATE())
GROUP BY
    f.id_funcionario,
    f.nome_usuario
ORDER BY valor_total_vendido DESC;

-- KPI VENDAS MES
SELECT
    SUM(e.total) AS valor_total_vendido,
    COUNT(*) AS total_vendas
FROM tbl_evento e
WHERE e.tipo = 'VENDA'
    AND e.status = 'CONCLUIDA'
    AND MONTH(e.data_hora_evento) = MONTH(CURDATE())
    AND YEAR(e.data_hora_evento) = YEAR(CURDATE());

-- KPI FATURAMENTO DIA
SELECT
    SUM(e.total) AS valor_total_vendido,
    COUNT(*) AS total_vendas
FROM tbl_evento e
WHERE e.tipo = 'VENDA'
    AND e.status = 'CONCLUIDA'
    AND DATE(e.data_hora_evento) = CURDATE();

-- VALIDAÇÕES
SELECT * FROM tbl_produto;

SELECT
    id_produto,
    nome,
    qtd_unidade,
    qtd_minimo
FROM tbl_produto
ORDER BY nome;

SELECT
    ub.id_unidade_bebida,
    p.nome,
    ub.ml_inicial,
    ub.ml_atual,
    ub.status
FROM tbl_unidade_bebida ub
INNER JOIN tbl_produto p
    ON p.id_produto = ub.id_produto
ORDER BY ub.id_unidade_bebida;

SELECT 
    p.id_produto,
    p.nome AS nome_produto,
    p.embalagem,
    IFNULL(ub.id_unidade_bebida, 'N/A') AS id_unidade,
    IFNULL(ub.ml_atual, 0) AS ml_disponivel_dose,
    IFNULL(ub.status, 'FECHADO') AS status_garrafa
FROM tbl_produto p
LEFT JOIN tbl_unidade_bebida ub 
    ON p.id_produto = ub.id_produto
ORDER BY ub.status DESC, p.nome;

SELECT
    p.id_produto,
    p.nome,
    c.categoria,
    p.qtd_unidade
FROM tbl_produto p
JOIN dmsao_categoria c
    ON p.id_categoria = c.id_categoria
WHERE p.id_produto = 11;