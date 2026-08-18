package com.sourcelens.module.execution.dto;

public record ExecutionCheckpointState(
        int sequenceNo,
        String stepKey,
        String inputSha256,
        String stateJson,
        long stateByteLength,
        String stateSha256
) {
}
