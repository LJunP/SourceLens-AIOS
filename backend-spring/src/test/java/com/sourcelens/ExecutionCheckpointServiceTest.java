package com.sourcelens;

import com.sourcelens.module.execution.dto.ExecutionPlanStep;
import com.sourcelens.module.execution.dto.ExecutionResumeState;
import com.sourcelens.module.execution.dto.ExecutionWorkflowPlan;
import com.sourcelens.module.execution.entity.ExecutionCheckpoint;
import com.sourcelens.module.execution.mapper.ExecutionCheckpointStore;
import com.sourcelens.module.execution.service.ExecutionCheckpointIntegrityException;
import com.sourcelens.module.execution.service.ExecutionCheckpointService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ExecutionCheckpointServiceTest {

    @Mock
    private ExecutionCheckpointStore checkpointStore;

    private final List<ExecutionCheckpoint> persisted = new ArrayList<>();
    private ExecutionCheckpointService service;

    @BeforeEach
    void setUp() {
        service = new ExecutionCheckpointService(checkpointStore);
        lenient().when(checkpointStore.lockTask(anyLong())).thenReturn(true);
        when(checkpointStore.list(anyLong()))
                .thenAnswer(invocation -> new ArrayList<>(persisted));
        lenient().doAnswer(invocation -> {
            ExecutionCheckpoint checkpoint = invocation.getArgument(0);
            checkpoint.setId((long) persisted.size() + 1);
            persisted.add(checkpoint);
            return null;
        }).when(checkpointStore).insert(any(ExecutionCheckpoint.class));
    }

    @Test
    void completeAndResume_shouldExposeOnlyNextStepAsExecutable() {
        ExecutionWorkflowPlan plan = plan();

        ExecutionResumeState first = service.completeCheckpoint(41L, plan, "plan", "{\"cursor\":1}");
        ExecutionResumeState second = service.completeCheckpoint(41L, plan, "execute", "{\"cursor\":2}");

        assertEquals(List.of("plan"), first.completedStepKeys());
        assertEquals(List.of("execute"), first.executableStepKeys());
        assertEquals(List.of("plan", "execute"), second.completedStepKeys());
        assertEquals(List.of("checkpoint"), second.executableStepKeys());
        assertFalse(second.complete());
    }

    @Test
    void identicalReplay_shouldBeIdempotentWithoutInsert() {
        ExecutionWorkflowPlan plan = plan();

        ExecutionResumeState initial = service.completeCheckpoint(41L, plan, "plan", "{\"cursor\":1}");
        ExecutionResumeState replay = service.completeCheckpoint(41L, plan, "plan", "{\"cursor\":1}");

        assertEquals(initial, replay);
        assertEquals(1, persisted.size());
        verify(checkpointStore, times(1)).insert(any(ExecutionCheckpoint.class));
    }

    @Test
    void conflictingReplay_shouldFailClosed() {
        ExecutionWorkflowPlan plan = plan();
        service.completeCheckpoint(41L, plan, "plan", "{\"cursor\":1}");

        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.completeCheckpoint(41L, plan, "plan", "{\"cursor\":999}")
        );

        assertEquals("CONFLICTING_CHECKPOINT_REWRITE", error.getReasonCode());
        assertEquals(1, persisted.size());
    }

    @Test
    void orderGap_shouldFailClosed() {
        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.completeCheckpoint(41L, plan(), "execute", "{}")
        );

        assertEquals("CHECKPOINT_ORDER_GAP", error.getReasonCode());
        assertTrue(persisted.isEmpty());
    }

    @Test
    void workflowDrift_shouldFailClosedEvenWhenCompletedPrefixIsUnchanged() {
        ExecutionWorkflowPlan original = plan();
        service.completeCheckpoint(41L, original, "plan", "{}");
        ExecutionWorkflowPlan changedFutureStep = new ExecutionWorkflowPlan("agent-run-v1", List.of(
                new ExecutionPlanStep("plan", "a".repeat(64)),
                new ExecutionPlanStep("execute", "f".repeat(64)),
                new ExecutionPlanStep("checkpoint", "c".repeat(64))
        ));

        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.resume(41L, changedFutureStep)
        );

        assertEquals("WORKFLOW_DRIFT", error.getReasonCode());
    }

    @Test
    void changedWorkflowIdentity_shouldNotCreateParallelHistoryForSameTask() {
        ExecutionWorkflowPlan original = plan();
        service.completeCheckpoint(41L, original, "plan", "{}");
        ExecutionWorkflowPlan renamed = new ExecutionWorkflowPlan("renamed-agent-run", original.steps());

        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.completeCheckpoint(41L, renamed, "plan", "{}")
        );

        assertEquals("CHECKPOINT_SCOPE_DRIFT", error.getReasonCode());
        assertEquals(1, persisted.size());
    }

    @Test
    void corruptedState_shouldFailClosed() {
        ExecutionWorkflowPlan plan = plan();
        service.completeCheckpoint(41L, plan, "plan", "{\"cursor\":1}");
        persisted.get(0).setStateJson("{\"cursor\":2}");

        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.resume(41L, plan)
        );

        assertEquals("STATE_INTEGRITY_DRIFT", error.getReasonCode());
    }

    @Test
    void nonPrefixHistory_shouldFailClosed() throws Exception {
        ExecutionWorkflowPlan plan = plan();
        byte[] state = "{}".getBytes(StandardCharsets.UTF_8);
        persisted.add(ExecutionCheckpoint.builder()
                .id(1L)
                .taskId(41L)
                .workflowId(plan.workflowId())
                .workflowSha256(plan.workflowSha256())
                .sequenceNo(1)
                .stepKey("execute")
                .inputSha256("b".repeat(64))
                .stateJson("{}")
                .stateByteLength((long) state.length)
                .stateSha256(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(state)))
                .status("COMPLETED")
                .build());

        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.resume(41L, plan)
        );

        assertEquals("NON_PREFIX_SEQUENCE", error.getReasonCode());
    }

    private ExecutionWorkflowPlan plan() {
        return new ExecutionWorkflowPlan("agent-run-v1", List.of(
                new ExecutionPlanStep("plan", "a".repeat(64)),
                new ExecutionPlanStep("execute", "b".repeat(64)),
                new ExecutionPlanStep("checkpoint", "c".repeat(64))
        ));
    }
}
