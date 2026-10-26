DROP DATABASE IF EXISTS adega_underground;
CREATE DATABASE adega_underground;
USE adega_underground;

-- 1. Tabela de Categorias
CREATE TABLE dmsao_categoria (
    id_categoria INT PRIMARY KEY AUTO_INCREMENT,
    categoria ENUM('BEBIDA UNIDADE', 'BEBIDA FRACIONADA', 'DIVERSOS', 'DRINK', 'COMBO') NOT NULL
);

-- 2. Tabela de Funcionários
CREATE TABLE tbl_funcionario (
    id_funcionario INT PRIMARY KEY AUTO_INCREMENT,
    nome_usuario VARCHAR(45) NOT NULL,
    senha_cripto VARCHAR(45) NOT NULL,
    cpf VARCHAR(11),
    celular VARCHAR(45),
    email VARCHAR(45)
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
    imagem VARCHAR(45),
    qtd_minimo INT DEFAULT 0,
    qtd_unidade INT DEFAULT 0,
    valor_compra INT NULL,

    id_produto_pai INT NULL,

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
    CONSTRAINT fk_evento_cliente FOREIGN KEY (tbl_cliente_id_cliente) REFERENCES tbl_cliente(id_cliente),
    CONSTRAINT fk_evento_funcionario FOREIGN KEY (tbl_funcionario_id_funcionario) REFERENCES tbl_funcionario(id_funcionario)
);

-- 6. Tabela de Itens do Evento (Relacionamento N:M entre Evento e Produto)
CREATE TABLE item_evento (
    id_evento INT NOT NULL,
    id_produto INT NOT NULL,
    quantidade INT NOT NULL,
    PRIMARY KEY (id_evento, id_produto),
    CONSTRAINT fk_item_evento FOREIGN KEY (id_evento) REFERENCES tbl_evento(id_evento),
    CONSTRAINT fk_item_produto FOREIGN KEY (id_produto) REFERENCES tbl_produto(id_produto)
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
    ml_inicial int(45),
    ml_atual INT,
    status ENUM('ABERTO', 'FECHADO') DEFAULT 'FECHADO',
    id_produto INT NOT NULL,
    CONSTRAINT fk_unidade_produto FOREIGN KEY (id_produto) REFERENCES tbl_produto(id_produto)
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
    permissao VARCHAR(45) NOT NULL
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



-- INSERSTS
INSERT INTO dmsao_permissao (permissao) VALUES
('Visualizar usuários'),
('Cadastrar usuários'),
('Editar usuários'),
('Desativar / ativar usuários'),
('Redefinir senha'),

('Visualizar produtos'),
('Cadastrar produtos'),
('Excluir / inativar produtos'),

('Visualizar estoque'),
('Entrada / recebimento'),
('Ajuste manual'),
('Perdas / quebras'),
('Histórico de movimentações'),

('Registrar venda'),
('Aplicar desconto'),
('Cancelar venda'),
('Histórico de vendas');

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
('admin', '123456', '11122233344', '11999998888', 'gerente@gmail.com'),
('caixa_lucas', '123456', '22233344455', '11988887777', 'lucas.caixa@adegaunderground.com'),
('barman_igor', '123456', '33344455566', '11977776666', 'igor.drinks@adegaunderground.com');

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

SELEcT * FROM tbl_funcionario;

-- GRAFICO Visao Detalhada de Vendas Diarias
SELECT 
    DAY(e.data_hora_evento) AS dia,
    SUM(
        p.preco * ie.quantidade
    ) AS valor_total_vendas
FROM tbl_evento e
INNER JOIN item_evento ie
    ON e.id_evento = ie.id_evento
INNER JOIN tbl_produto p
    ON ie.id_produto = p.id_produto
WHERE e.tipo = 'VENDA'
    AND MONTH(e.data_hora_evento) = MONTH(CURDATE())
GROUP BY DAY(e.data_hora_evento)
ORDER BY dia;

-- RANKING POR VENDEDOR
SELECT 
    f.id_funcionario,
    f.nome_usuario AS vendedor,
    COUNT(DISTINCT e.id_evento) AS quantidade_vendas,
    SUM(
        p.preco * ie.quantidade
    ) AS valor_total_vendido
FROM tbl_funcionario f
INNER JOIN tbl_evento e
    ON f.id_funcionario = e.tbl_funcionario_id_funcionario
INNER JOIN item_evento ie
    ON e.id_evento = ie.id_evento
INNER JOIN tbl_produto p
    ON ie.id_produto = p.id_produto
WHERE e.tipo = 'VENDA'
    AND MONTH(e.data_hora_evento) = MONTH(CURDATE())
    AND YEAR(e.data_hora_evento) = YEAR(CURDATE())
GROUP BY 
    f.id_funcionario,
    f.nome_usuario
ORDER BY valor_total_vendido DESC;

-- KPI VENDAS MES
SELECT 
	SUM(
        c.preco * b.quantidade
	) AS valor_total_vendido,
    COUNT(DISTINCT a.id_evento) as total_vendas
FROM
	tbl_evento as a
INNER JOIN item_evento as b
	ON a.id_evento = b.id_evento
INNER JOIN tbl_produto as c
	ON b.id_produto = c.id_produto
WHERE
	a.tipo = 'VENDA'
    AND MONTH(a.data_hora_evento) = MONTH(CURDATE())
    AND YEAR(a.data_hora_evento) = YEAR(CURDATE());
    
-- KPI FATURAMENTO DIA
SELECT 
	SUM(
        c.preco * b.quantidade
	) AS valor_total_vendido,
    COUNT(DISTINCT a.id_evento) as total_vendas
FROM
	tbl_evento as a
INNER JOIN item_evento as b
	ON a.id_evento = b.id_evento
INNER JOIN tbl_produto as c
	ON b.id_produto = c.id_produto
WHERE
	a.tipo = 'VENDA'
    AND DAY(a.data_hora_evento) = DAY(CURDATE())
    AND MONTH(a.data_hora_evento) = MONTH(CURDATE())
    AND YEAR(a.data_hora_evento) = YEAR(CURDATE());
    
    
    
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