# P1-011 Environment Snapshot

Local, deterministic capture and verification for the P1 `EnvironmentSnapshot`
contract. The implementation accepts only explicit source, target-runtime,
dependency, model, prompt, tool and policy declarations. It performs no network
or provider access.

Run the frozen Quality matrix locally:

```sh
node evaluation-harness/environment/self-test.mjs
```
