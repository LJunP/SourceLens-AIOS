package com.sourcelens.module.execution.mapper;

import com.sourcelens.module.execution.entity.ExecutionCheckpoint;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
@RequiredArgsConstructor
public class ExecutionCheckpointStore {

    private final JdbcTemplate jdbcTemplate;

    public boolean lockTask(Long taskId) {
        return !jdbcTemplate.queryForList(
                "select id from execution_tasks where id = ? for update", Long.class, taskId
        ).isEmpty();
    }

    public List<ExecutionCheckpoint> list(Long taskId) {
        return jdbcTemplate.query(
                """
                select id, task_id, workflow_id, workflow_sha256, sequence_no, step_key,
                       input_sha256, state_json, state_byte_length, state_sha256, status,
                       created_at, updated_at
                from execution_checkpoints
                where task_id = ?
                order by sequence_no asc, id asc
                """,
                (rs, rowNum) -> ExecutionCheckpoint.builder()
                        .id(rs.getLong("id"))
                        .taskId(rs.getLong("task_id"))
                        .workflowId(rs.getString("workflow_id"))
                        .workflowSha256(rs.getString("workflow_sha256"))
                        .sequenceNo(rs.getInt("sequence_no"))
                        .stepKey(rs.getString("step_key"))
                        .inputSha256(rs.getString("input_sha256"))
                        .stateJson(rs.getString("state_json"))
                        .stateByteLength(rs.getLong("state_byte_length"))
                        .stateSha256(rs.getString("state_sha256"))
                        .status(rs.getString("status"))
                        .createdAt(rs.getTimestamp("created_at").toLocalDateTime())
                        .updatedAt(rs.getTimestamp("updated_at").toLocalDateTime())
                        .build(),
                taskId
        );
    }

    public void insert(ExecutionCheckpoint checkpoint) {
        jdbcTemplate.update(
                """
                insert into execution_checkpoints
                    (task_id, workflow_id, workflow_sha256, sequence_no, step_key,
                     input_sha256, state_json, state_byte_length, state_sha256, status)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                checkpoint.getTaskId(), checkpoint.getWorkflowId(), checkpoint.getWorkflowSha256(),
                checkpoint.getSequenceNo(), checkpoint.getStepKey(), checkpoint.getInputSha256(),
                checkpoint.getStateJson(), checkpoint.getStateByteLength(), checkpoint.getStateSha256(),
                checkpoint.getStatus()
        );
    }
}
