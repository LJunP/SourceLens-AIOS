package com.sourcelens.module.execution.dto;

import java.util.List;
import java.util.Optional;

public record ExecutionResumeState(
        Long taskId,
        String workflowId,
        String workflowSha256,
        List<ExecutionCheckpointState> acceptedCheckpoints,
        List<String> completedStepKeys,
        Optional<ExecutionPlanStep> nextStep,
        List<String> executableStepKeys
) {
    public ExecutionResumeState {
        acceptedCheckpoints = List.copyOf(acceptedCheckpoints);
        completedStepKeys = List.copyOf(completedStepKeys);
        nextStep = nextStep == null ? Optional.empty() : nextStep;
        executableStepKeys = List.copyOf(executableStepKeys);
        if (executableStepKeys.size() > 1 ||
                (nextStep.isEmpty() && !executableStepKeys.isEmpty()) ||
                (nextStep.isPresent() && !executableStepKeys.equals(List.of(nextStep.get().stepKey())))) {
            throw new IllegalArgumentException("可执行步骤必须精确等于恢复游标的下一步");
        }
        if (!acceptedCheckpoints.stream().map(ExecutionCheckpointState::stepKey).toList()
                .equals(completedStepKeys)) {
            throw new IllegalArgumentException("完成步骤必须精确对应已验证的持久检查点");
        }
    }

    public boolean complete() {
        return nextStep.isEmpty();
    }
}
