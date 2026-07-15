# AIOS-P1-001 frozen evaluator

This evaluator is owned by the Quality and Evaluation role. It evaluates only the
visible deterministic harness-conformance fixture. It does not measure B0, VTSR,
Repository Intelligence, Agent capability, production readiness, or hostile-principal
resistance.

The command interface is:

```text
/usr/local/bin/node evaluation-harness/evaluator/evaluate.mjs \
  --task TASK_SPEC \
  --environment ENVIRONMENT_SNAPSHOT \
  --configuration SYSTEM_CONFIGURATION \
  --run-record RUN_RECORD \
  --result RESULT_ARTIFACT \
  --oracle evaluation-harness/fixtures/oracle/oracle.json \
  --schema-root docs/aios/schemas \
  --artifact-root REPOSITORY_ROOT
```

Exit status `0` means the frozen conformance oracle passed, `1` means the run was
validly evaluated and failed, and `2` means evaluator input or invocation was invalid.
The JSON written to stdout is canonical and contains no timestamp or host path, so an
unchanged run can be compared byte-for-byte during replay.

`schema-validator.mjs` implements only the JSON Schema keywords exercised by the four
accepted P1 contract schemas. It is not a general JSON Schema implementation.
