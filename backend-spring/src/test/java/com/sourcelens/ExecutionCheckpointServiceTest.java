package com.sourcelens;

import com.sourcelens.module.execution.dto.ExecutionPlanStep;
import com.sourcelens.module.execution.dto.ExecutionResumeState;
import com.sourcelens.module.execution.dto.ExecutionWorkflowPlan;
import com.sourcelens.module.execution.entity.ExecutionCheckpoint;
import com.sourcelens.module.execution.entity.ExecutionCheckpointHead;
import com.sourcelens.module.execution.mapper.ExecutionCheckpointStore;
import com.sourcelens.module.execution.service.ExecutionCheckpointIntegrityException;
import com.sourcelens.module.execution.service.ExecutionCheckpointService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
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
    private ExecutionCheckpointHead persistedHead;
    private ExecutionCheckpointService service;

    @BeforeEach
    void setUp() {
        service = new ExecutionCheckpointService(checkpointStore);
        lenient().when(checkpointStore.lockTask(anyLong())).thenReturn(true);
        lenient().when(checkpointStore.taskExists(anyLong())).thenReturn(true);
        lenient().when(checkpointStore.list(anyLong()))
                .thenAnswer(invocation -> new ArrayList<>(persisted));
        lenient().when(checkpointStore.getHead(anyLong())).thenAnswer(invocation -> persistedHead);
        lenient().doAnswer(invocation -> {
            ExecutionCheckpoint checkpoint = invocation.getArgument(0);
            checkpoint.setId((long) persisted.size() + 1);
            persisted.add(checkpoint);
            return null;
        }).when(checkpointStore).insert(any(ExecutionCheckpoint.class));
        lenient().doAnswer(invocation -> {
            persistedHead = invocation.getArgument(0);
            return null;
        }).when(checkpointStore).insertHead(any(ExecutionCheckpointHead.class));
        lenient().when(checkpointStore.advanceHead(anyLong(), anyInt(), anyString(),
                anyInt(), anyString())).thenAnswer(invocation -> {
            persistedHead.setAcceptedCount(invocation.getArgument(3));
            persistedHead.setChainSha256(invocation.getArgument(4));
            return 1;
        });
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

        assertEquals("CHECKPOINT_HEAD_SCOPE_DRIFT", error.getReasonCode());
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

        assertEquals("CHECKPOINT_HEAD_SCOPE_DRIFT", error.getReasonCode());
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
    void nonPrefixHistory_shouldFailClosed() {
        ExecutionWorkflowPlan plan = plan();
        service.completeCheckpoint(41L, plan, "plan", "{}");
        persisted.get(0).setSequenceNo(1);

        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.resume(41L, plan)
        );

        assertEquals("NON_PREFIX_SEQUENCE", error.getReasonCode());
    }

    @Test
    void truncatedTail_shouldFailClosedAgainstCommittedHead() {
        ExecutionWorkflowPlan plan = plan();
        service.completeCheckpoint(41L, plan, "plan", "{}");
        service.completeCheckpoint(41L, plan, "execute", "{}");
        persisted.remove(1);

        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.resume(41L, plan)
        );

        assertEquals("CHECKPOINT_HEAD_COUNT_DRIFT", error.getReasonCode());
    }

    @Test
    void missingParentTask_shouldFailClosedOnResume() {
        when(checkpointStore.taskExists(99L)).thenReturn(false);

        ExecutionCheckpointIntegrityException error = assertThrows(
                ExecutionCheckpointIntegrityException.class,
                () -> service.resume(99L, plan())
        );

        assertEquals("TASK_NOT_FOUND", error.getReasonCode());
    }

    private ExecutionWorkflowPlan plan() {
        return new ExecutionWorkflowPlan("agent-run-v1", List.of(
                new ExecutionPlanStep("plan", "a".repeat(64)),
                new ExecutionPlanStep("execute", "b".repeat(64)),
                new ExecutionPlanStep("checkpoint", "c".repeat(64))
        ));
    }
}
