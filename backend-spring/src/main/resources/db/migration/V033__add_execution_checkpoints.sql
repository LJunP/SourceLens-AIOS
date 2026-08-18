CREATE TABLE IF NOT EXISTS `execution_checkpoints` (
    `id`                BIGINT AUTO_INCREMENT PRIMARY KEY,
    `task_id`           BIGINT NOT NULL,
    `workflow_id`       VARCHAR(120) NOT NULL,
    `workflow_sha256`   CHAR(64) NOT NULL,
    `sequence_no`       INT NOT NULL,
    `step_key`          VARCHAR(120) NOT NULL,
    `input_sha256`      CHAR(64) NOT NULL,
    `state_json`        LONGTEXT NOT NULL,
    `state_byte_length` BIGINT NOT NULL,
    `state_sha256`      CHAR(64) NOT NULL,
    `status`            VARCHAR(20) NOT NULL DEFAULT 'COMPLETED',
    `created_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_execution_checkpoint_sequence` (`task_id`, `sequence_no`),
    UNIQUE KEY `uk_execution_checkpoint_step` (`task_id`, `step_key`),
    INDEX `idx_execution_checkpoint_resume` (`task_id`, `sequence_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='执行工作流的持久完成检查点';
