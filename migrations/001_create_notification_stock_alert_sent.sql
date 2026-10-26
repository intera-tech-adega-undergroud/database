-- 001. Tabela de alertas de estoque enviados || Micro-serviço (notification-service)
-- Trava + registro: no máximo 1 alerta por produto por dia (America/Sao_Paulo).
-- Sem FK para tbl_produto (desacoplamento do monólito).
-- Idempotente: pode ser executado mais de uma vez sem erro.
USE adega_underground;

CREATE TABLE IF NOT EXISTS notification_stock_alert_sent (
    product_id INT NOT NULL,
    reference_date DATE NOT NULL,
    event_id CHAR(36) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (product_id, reference_date),
    CONSTRAINT chk_stock_alert_sent_severity
        CHECK (severity IN ('CRITICAL', 'HIGH', 'MEDIUM'))
);
