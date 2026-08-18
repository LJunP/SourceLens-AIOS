package com.sourcelens.module.execution.dto;

import java.util.Objects;
import java.util.regex.Pattern;

public record ExecutionPlanStep(String stepKey, String inputSha256) {

    private static final Pattern SHA256 = Pattern.compile("[0-9a-f]{64}");

    public ExecutionPlanStep {
        stepKey = Objects.requireNonNull(stepKey, "stepKey 不能为空");
        inputSha256 = Objects.requireNonNull(inputSha256, "inputSha256 不能为空");
        if (stepKey.isBlank() || stepKey.length() > 120) {
            throw new IllegalArgumentException("stepKey 长度必须在 1 到 120 之间");
        }
        if (!SHA256.matcher(inputSha256).matches()) {
            throw new IllegalArgumentException("inputSha256 必须是小写 SHA-256");
        }
    }
}
