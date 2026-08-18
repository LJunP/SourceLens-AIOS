package com.sourcelens.module.execution.service;

import com.sourcelens.module.execution.dto.ExecutionPlanStep;
import com.sourcelens.module.execution.dto.ExecutionCheckpointState;
import com.sourcelens.module.execution.dto.ExecutionResumeState;
import com.sourcelens.module.execution.dto.ExecutionWorkflowPlan;
import com.sourcelens.module.execution.entity.ExecutionCheckpoint;
import com.sourcelens.module.execution.entity.ExecutionCheckpointHead;
import com.sourcelens.module.execution.mapper.ExecutionCheckpointStore;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;

@Service
@RequiredArgsConstructor
public class ExecutionCheckpointService {

    private static final String COMPLETED = "COMPLETED";
    private static final String TASK_BINDING_DOMAIN = "sourcelens-execution-task-binding/v1\n";
    private static final String CHAIN_DOMAIN = "sourcelens-execution-checkpoint-chain/v1\n";

    private final ExecutionCheckpointStore checkpointStore;

    @Transactional(readOnly = true)
    public ExecutionResumeState resume(Long taskId, ExecutionWorkflowPlan plan) {
        validateTaskId(taskId);
        Objects.requireNonNull(plan, "plan 不能为空");
        if (!checkpointStore.taskExists(taskId)) {
            throw integrity("TASK_NOT_FOUND", "执行任务不存在: " + taskId);
        }
        return restore(taskId, plan, checkpointStore.list(taskId), checkpointStore.getHead(taskId));
    }

    @Transactional
    public ExecutionResumeState completeCheckpoint(Long taskId, ExecutionWorkflowPlan plan,
                                                   String stepKey, String stateJson) {
        validateTaskId(taskId);
        Objects.requireNonNull(plan, "plan 不能为空");
        Objects.requireNonNull(stepKey, "stepKey 不能为空");
        Objects.requireNonNull(stateJson, "stateJson 不能为空");
        if (!checkpointStore.lockTask(taskId)) {
            throw integrity("TASK_NOT_FOUND", "执行任务不存在: " + taskId);
        }

        List<ExecutionCheckpoint> checkpoints = checkpointStore.list(taskId);
        ExecutionCheckpointHead head = checkpointStore.getHead(taskId);
        ExecutionResumeState current = restore(taskId, plan, checkpoints, head);
        int target = indexOf(plan.steps(), stepKey);
        if (target < 0) {
            throw integrity("STEP_NOT_IN_PLAN", "步骤不属于当前工作流: " + stepKey);
        }

        byte[] stateBytes = stateJson.getBytes(StandardCharsets.UTF_8);
        String stateSha256 = sha256(stateBytes);
        if (target < checkpoints.size()) {
            ExecutionCheckpoint existing = checkpoints.get(target);
            if (!existing.getStateByteLength().equals((long) stateBytes.length) ||
                    !existing.getStateSha256().equals(stateSha256) ||
                    !existing.getStateJson().equals(stateJson)) {
                throw integrity("CONFLICTING_CHECKPOINT_REWRITE",
                        "已完成检查点不允许用不同状态重写: " + stepKey);
            }
            return current;
        }
        if (target != checkpoints.size()) {
            throw integrity("CHECKPOINT_ORDER_GAP", "只能提交恢复游标指向的下一步骤: " + stepKey);
        }

        ExecutionPlanStep planStep = plan.steps().get(target);
        checkpointStore.insert(ExecutionCheckpoint.builder()
                .taskId(taskId)
                .taskBindingSha256(taskBindingSha256(taskId))
                .workflowId(plan.workflowId())
                .workflowSha256(plan.workflowSha256())
                .sequenceNo(target)
                .stepKey(planStep.stepKey())
                .inputSha256(planStep.inputSha256())
                .stateJson(stateJson)
                .stateByteLength((long) stateBytes.length)
                .stateSha256(stateSha256)
                .status(COMPLETED)
                .build());
        String nextChainSha256 = chainSha256(taskId, plan, checkpoints, target, planStep, stateSha256);
        if (head == null) {
            checkpointStore.insertHead(ExecutionCheckpointHead.builder()
                    .taskId(taskId)
                    .workflowId(plan.workflowId())
                    .workflowSha256(plan.workflowSha256())
                    .acceptedCount(1)
                    .chainSha256(nextChainSha256)
                    .build());
        } else if (checkpointStore.advanceHead(taskId, head.getAcceptedCount(), head.getChainSha256(),
                target + 1, nextChainSha256) != 1) {
            throw integrity("CHECKPOINT_HEAD_CONCURRENT_DRIFT", "检查点提交头发生并发漂移");
        }
        return restore(taskId, plan, checkpointStore.list(taskId), checkpointStore.getHead(taskId));
    }

    private ExecutionResumeState restore(Long taskId, ExecutionWorkflowPlan plan,
                                         List<ExecutionCheckpoint> checkpoints,
                                         ExecutionCheckpointHead head) {
        validateHead(taskId, plan, checkpoints, head);
        if (checkpoints.size() > plan.steps().size()) {
            throw integrity("CHECKPOINT_COUNT_EXCEEDS_PLAN", "检查点数量超过工作流步骤数量");
        }
        List<String> completed = new ArrayList<>();
        List<ExecutionCheckpointState> accepted = new ArrayList<>();
        Set<String> seenKeys = new HashSet<>();
        Set<Integer> seenSequences = new HashSet<>();
        for (int i = 0; i < checkpoints.size(); i++) {
            ExecutionCheckpoint checkpoint = checkpoints.get(i);
            ExecutionPlanStep expected = plan.steps().get(i);
            if (!Objects.equals(checkpoint.getTaskId(), taskId) ||
                    !Objects.equals(checkpoint.getWorkflowId(), plan.workflowId())) {
                throw integrity("CHECKPOINT_SCOPE_DRIFT", "检查点任务或工作流身份漂移");
            }
            if (!taskBindingSha256(taskId).equals(checkpoint.getTaskBindingSha256())) {
                throw integrity("TASK_BINDING_DRIFT", "检查点与原执行任务的持久绑定不一致");
            }
            if (!Objects.equals(checkpoint.getSequenceNo(), i) || !seenSequences.add(checkpoint.getSequenceNo())) {
                throw integrity("NON_PREFIX_SEQUENCE", "检查点序列不是从 0 开始的连续前缀");
            }
            if (!seenKeys.add(checkpoint.getStepKey())) {
                throw integrity("DUPLICATE_STEP_KEY", "检查点包含重复 stepKey");
            }
            if (!COMPLETED.equals(checkpoint.getStatus())) {
                throw integrity("NON_COMPLETED_CHECKPOINT", "恢复记录包含非完成检查点");
            }
            if (!plan.workflowSha256().equals(checkpoint.getWorkflowSha256())) {
                throw integrity("WORKFLOW_DRIFT", "持久检查点与当前工作流哈希不一致");
            }
            if (!expected.stepKey().equals(checkpoint.getStepKey()) ||
                    !expected.inputSha256().equals(checkpoint.getInputSha256())) {
                throw integrity("PLAN_PREFIX_DRIFT", "持久检查点不是当前计划的精确前缀");
            }
            validateState(checkpoint);
            completed.add(checkpoint.getStepKey());
            accepted.add(new ExecutionCheckpointState(
                    checkpoint.getSequenceNo(), checkpoint.getStepKey(), checkpoint.getInputSha256(),
                    checkpoint.getStateJson(), checkpoint.getStateByteLength(), checkpoint.getStateSha256()
            ));
        }

        Optional<ExecutionPlanStep> next = checkpoints.size() == plan.steps().size()
                ? Optional.empty()
                : Optional.of(plan.steps().get(checkpoints.size()));
        List<String> executable = next.map(step -> List.of(step.stepKey())).orElseGet(List::of);
        return new ExecutionResumeState(taskId, plan.workflowId(), plan.workflowSha256(),
                accepted, completed, next, executable);
    }

    private void validateHead(Long taskId, ExecutionWorkflowPlan plan,
                              List<ExecutionCheckpoint> checkpoints, ExecutionCheckpointHead head) {
        if (head == null) {
            if (!checkpoints.isEmpty()) {
                throw integrity("CHECKPOINT_HEAD_MISSING", "存在检查点但提交头缺失");
            }
            return;
        }
        if (!Objects.equals(head.getTaskId(), taskId) ||
                !Objects.equals(head.getWorkflowId(), plan.workflowId()) ||
                !Objects.equals(head.getWorkflowSha256(), plan.workflowSha256())) {
            throw integrity("CHECKPOINT_HEAD_SCOPE_DRIFT", "检查点提交头的任务或工作流身份漂移");
        }
        if (head.getAcceptedCount() == null || head.getAcceptedCount() <= 0 ||
                head.getAcceptedCount() != checkpoints.size()) {
            throw integrity("CHECKPOINT_HEAD_COUNT_DRIFT", "持久提交头与检查点数量不一致");
        }
        String expectedChain = chainSha256(taskId, plan, checkpoints,
                checkpoints.size() - 1, null, null);
        if (!Objects.equals(head.getChainSha256(), expectedChain)) {
            throw integrity("CHECKPOINT_CHAIN_DRIFT", "持久检查点链哈希不一致");
        }
    }

    private String chainSha256(Long taskId, ExecutionWorkflowPlan plan,
                               List<ExecutionCheckpoint> existing, int lastIndex,
                               ExecutionPlanStep appendedStep, String appendedStateSha256) {
        String chain = sha256((CHAIN_DOMAIN + taskId + ':' + plan.workflowSha256())
                .getBytes(StandardCharsets.UTF_8));
        for (int i = 0; i <= lastIndex; i++) {
            ExecutionCheckpoint checkpoint = i < existing.size() ? existing.get(i) : null;
            String stepKey = checkpoint == null ? appendedStep.stepKey() : checkpoint.getStepKey();
            String inputSha256 = checkpoint == null ? appendedStep.inputSha256() : checkpoint.getInputSha256();
            String stateSha256 = checkpoint == null ? appendedStateSha256 : checkpoint.getStateSha256();
            chain = sha256((chain + ':' + i + ':' +
                    stepKey.getBytes(StandardCharsets.UTF_8).length + ':' + stepKey + ':' +
                    inputSha256 + ':' + stateSha256).getBytes(StandardCharsets.UTF_8));
        }
        return chain;
    }

    private String taskBindingSha256(Long taskId) {
        return sha256((TASK_BINDING_DOMAIN + taskId).getBytes(StandardCharsets.UTF_8));
    }

    private void validateState(ExecutionCheckpoint checkpoint) {
        if (checkpoint.getStateJson() == null || checkpoint.getStateByteLength() == null ||
                checkpoint.getStateSha256() == null) {
            throw integrity("STATE_IDENTITY_MISSING", "检查点状态身份不完整");
        }
        byte[] bytes = checkpoint.getStateJson().getBytes(StandardCharsets.UTF_8);
        if (checkpoint.getStateByteLength() != bytes.length ||
                !checkpoint.getStateSha256().equals(sha256(bytes))) {
            throw integrity("STATE_INTEGRITY_DRIFT", "检查点状态 bytes 或 SHA-256 已漂移");
        }
    }

    private int indexOf(List<ExecutionPlanStep> steps, String stepKey) {
        for (int i = 0; i < steps.size(); i++) {
            if (steps.get(i).stepKey().equals(stepKey)) {
                return i;
            }
        }
        return -1;
    }

    private void validateTaskId(Long taskId) {
        if (taskId == null || taskId <= 0) {
            throw new IllegalArgumentException("taskId 必须为正数");
        }
    }

    private String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("JDK 缺少 SHA-256", e);
        }
    }

    private ExecutionCheckpointIntegrityException integrity(String reasonCode, String message) {
        return new ExecutionCheckpointIntegrityException(reasonCode, message);
    }
}
