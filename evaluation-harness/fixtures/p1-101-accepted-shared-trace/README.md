# P1-101 Quality Fixture Freeze

This directory is owned by the independent Quality fixture builder for
`AIOS-P1-101_ACCEPTED_SHARED_EXECUTION_OBSERVABLE_TRACE`.

The positive plan invokes the already accepted canonical P1-097 adapter
configurations through the new P1-101 worker. It does not copy or modify the
accepted adapter, harness, recording, replay or fixture bytes.

Every negative case is materialized in a unique, absent output root. A
`PRE_EXECUTION` case must reject with `target_execution_count=0`. A
`POST_EXECUTION` case must start from its own fresh accepted adapter run,
record exactly one target execution, and reject before trace admission.

The fixtures only test the cooperative-local offline claim. They do not claim
model performance, provider access, network isolation or hostile-principal
security.
