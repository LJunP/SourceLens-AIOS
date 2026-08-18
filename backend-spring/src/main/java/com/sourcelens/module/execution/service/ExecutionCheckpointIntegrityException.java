package com.sourcelens.module.execution.service;

public class ExecutionCheckpointIntegrityException extends IllegalStateException {

    private final String reasonCode;

    public ExecutionCheckpointIntegrityException(String reasonCode, String message) {
        super(message);
        this.reasonCode = reasonCode;
    }

    public String getReasonCode() {
        return reasonCode;
    }
}
