package com.sourcelens.module.execution.dto;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Objects;

public record ExecutionWorkflowPlan(String workflowId, List<ExecutionPlanStep> steps, String workflowSha256) {

    private static final String HASH_DOMAIN = "sourcelens-execution-workflow/v1\n";

    public ExecutionWorkflowPlan(String workflowId, List<ExecutionPlanStep> steps) {
        this(workflowId, immutableSteps(steps), calculateHash(workflowId, steps));
    }

    public ExecutionWorkflowPlan {
        workflowId = Objects.requireNonNull(workflowId, "workflowId 不能为空");
        steps = immutableSteps(steps);
        if (workflowId.isBlank() || workflowId.length() > 120) {
            throw new IllegalArgumentException("workflowId 长度必须在 1 到 120 之间");
        }
        if (steps.isEmpty()) {
            throw new IllegalArgumentException("工作流至少需要一个步骤");
        }
        HashSet<String> keys = new HashSet<>();
        for (ExecutionPlanStep step : steps) {
            if (!keys.add(step.stepKey())) {
                throw new IllegalArgumentException("工作流 stepKey 必须唯一: " + step.stepKey());
            }
        }
        String expected = calculateHash(workflowId, steps);
        if (!expected.equals(workflowSha256)) {
            throw new IllegalArgumentException("workflowSha256 与计划内容不一致");
        }
    }

    private static List<ExecutionPlanStep> immutableSteps(List<ExecutionPlanStep> steps) {
        return List.copyOf(Objects.requireNonNull(steps, "steps 不能为空"));
    }

    private static String calculateHash(String workflowId, List<ExecutionPlanStep> steps) {
        Objects.requireNonNull(workflowId, "workflowId 不能为空");
        List<ExecutionPlanStep> immutable = immutableSteps(steps);
        StringBuilder canonical = new StringBuilder(HASH_DOMAIN)
                .append(workflowId.getBytes(StandardCharsets.UTF_8).length)
                .append(':').append(workflowId).append('\n');
        for (ExecutionPlanStep step : immutable) {
            canonical.append(step.stepKey().getBytes(StandardCharsets.UTF_8).length)
                    .append(':').append(step.stepKey()).append(':')
                    .append(step.inputSha256()).append('\n');
        }
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(canonical.toString().getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("JDK 缺少 SHA-256", e);
        }
    }
}
