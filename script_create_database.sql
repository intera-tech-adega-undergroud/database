DROP DATABASE adega_underground;
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
    nivel_acesso VARCHAR(45),
    cpf VARCHAR(11) UNIQUE,
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
    CONSTRAINT fk_produto_categoria FOREIGN KEY (id_categoria) REFERENCES dmsao_categoria(id_categoria)
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
    id_item INT PRIMARY KEY AUTO_INCREMENT,
    id_evento INT NOT NULL,
    id_produto INT NOT NULL,
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
    ml_inicial VARCHAR(45),
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







-- INSERSTS

-- Inserindo Categorias
INSERT INTO dmsao_categoria (categoria) VALUES 
('BEBIDA UNIDADE'), ('BEBIDA FRACIONADA'), ('COMBO');

-- Inserindo Funcionário e Cliente
INSERT INTO tbl_funcionario (nome_usuario, senha_cripto, nivel_acesso) 
VALUES ('admin', 'hash_segura_123', 'GERENTE');

INSERT INTO tbl_cliente (nome, compra_fiado, saldo_devedor) 
VALUES ('Cliente Particular', 0, 0.00);

-- Inserindo Produtos (Tabela Auxiliar)
INSERT INTO tbl_produto (nome, preco, id_categoria, volume_ml) VALUES 
('Cerveja Lata 350ml', 6.00, 1, 350),
('Garrafa Gin 750ml', 120.00, 2, 750),
('Energético 250ml', 12.00, 1, 250);

-- EVENTO 1: Recebimento de Estoque (Entrada)
-- Registramos o recebimento de 50 latas de cerveja
INSERT INTO tbl_evento (tipo, descricao, tbl_funcionario_id_funcionario, pago) 
VALUES ('RECEBIMENTO', 'Compra de 50 unidades de Cerveja Lata', 1, 1);
SET @ultimo_evento = LAST_INSERT_ID();
-- Inserimos 50 itens (num sistema real, isso seria um loop ou uma tabela de quantidade no item)
-- Para este exemplo, vamos simular que cada item_evento representa uma unidade ou um lote
INSERT INTO item_evento (id_evento, id_produto) VALUES (@ultimo_evento, 1); 

-- EVENTO 2: Venda (Saída)
INSERT INTO tbl_evento (tipo, forma_pagamento, tbl_cliente_id_cliente, tbl_funcionario_id_funcionario, pago) 
VALUES ('VENDA', 'PIX', 1, 1, 1);
SET @venda_id = LAST_INSERT_ID();
INSERT INTO item_evento (id_evento, id_produto) VALUES (@venda_id, 1), (@venda_id, 1); -- Vendeu 2 latas

-- EVENTO 3: Perda (Saída por quebra)
INSERT INTO tbl_evento (tipo, descricao, tbl_funcionario_id_funcionario, pago) 
VALUES ('PERDA', 'Lata amassada/vazada no transporte', 1, 1);
INSERT INTO item_evento (id_evento, id_produto) VALUES (LAST_INSERT_ID(), 1);




-- QUERYs UTEIS

SELECT 
    p.nome AS Produto,
    SUM(CASE WHEN e.tipo = 'RECEBIMENTO' THEN 1 ELSE 0 END) AS Entradas,
    SUM(CASE WHEN e.tipo IN ('VENDA', 'PERDA') THEN 1 ELSE 0 END) AS Saidas,
    (SUM(CASE WHEN e.tipo = 'RECEBIMENTO' THEN 1 ELSE 0 END) - 
     SUM(CASE WHEN e.tipo IN ('VENDA', 'PERDA') THEN 1 ELSE 0 END)) AS Saldo_Atual
FROM tbl_produto p
JOIN item_evento ie ON p.id_produto = ie.id_produto
JOIN tbl_evento e ON ie.id_evento = e.id_evento
GROUP BY p.id_produto;


SELECT 
    p.nome, 
    COUNT(ie.id_item) AS Qtd_Perdida,
    SUM(p.preco) AS Valor_Prejuizo,
    e.descricao AS Motivo
FROM tbl_evento e
JOIN item_evento ie ON e.id_evento = ie.id_evento
JOIN tbl_produto p ON ie.id_produto = p.id_produto
WHERE e.tipo = 'PERDA'
GROUP BY p.id_produto;


SELECT 
    forma_pagamento, 
    SUM(p.preco) AS Total_Arrecadado
FROM tbl_evento e
JOIN item_evento ie ON e.id_evento = ie.id_evento
JOIN tbl_produto p ON ie.id_produto = p.id_produto
WHERE e.tipo = 'VENDA'
GROUP BY forma_pagamento;