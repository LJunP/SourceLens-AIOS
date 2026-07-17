export function classifyCommandResult({ exitCode, signal }) {
  if (signal) return { status: "interrupted", signal };
  return { status: "success", exitCode };
}
