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
public class ExecutionCheckpoint {

    private Long id;
    private Long taskId;
    private String workflowId;
    private String workflowSha256;
    private Integer sequenceNo;
    private String stepKey;
    private String inputSha256;
    private String stateJson;
    private Long stateByteLength;
    private String stateSha256;
    private String status;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}
