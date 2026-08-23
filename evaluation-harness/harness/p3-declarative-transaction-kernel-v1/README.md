# P3 Declarative Transaction Kernel Foundation

This task-local foundation defines one content-addressed declarative machine specification, a generic interpreter, and an independently implemented full-replay verifier for the three frozen ETSK findings. It contains no Product implementation and has no package dependencies.

The machine specification is the sole domain-semantic authority. The interpreter executes only its closed, versioned operator algebra. The verifier does not import or call the interpreter; it independently selects transitions, applies effects, enforces invariants and cleanup algebra, recomputes results, and reconstructs aggregate and terminal-replay verdicts from the initial state and recorded events.

Run all checks only through the authorized Node binary inside the exact deny-network sandbox:

```sh
/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)' /opt/homebrew/Cellar/node@22/22.23.2/bin/node evaluation-harness/harness/p3-declarative-transaction-kernel-v1/tools/run-foundation.mjs --check
```

`--write` atomically creates the seven canonical JSON reports once. `--verify-installed` reconstructs every report and requires byte equality. Neither mode uses Docker, network, providers, secrets, credentials, remote state, production, public effects, or Product source.
