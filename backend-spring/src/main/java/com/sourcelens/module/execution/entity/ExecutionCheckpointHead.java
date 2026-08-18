package com.sourcelens.module.execution.entity;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ExecutionCheckpointHead {

    private Long taskId;
    private String workflowId;
    private String workflowSha256;
    private Integer acceptedCount;
    private String chainSha256;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
