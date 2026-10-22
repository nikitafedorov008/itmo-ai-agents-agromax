// Only server-confirmed terminal agent failures may start a fresh billable run.
// Network errors and IN_PROGRESS are ambiguous: preserve their operation ID.
const terminalCodes = new Set([
  "AGENT_TIMEOUT",
  "PROVIDER_ERROR",
  "INVALID_MODEL_OUTPUT",
  "INVALID_TOOL_ARGUMENTS",
  "TOOL_LIMIT",
  "AGENT_LIMIT",
  "AGENT_ERROR",
  "AGENT_FAILED",
  "RUN_INTERRUPTED",
  "WEATHER_UNAVAILABLE",
]);
export function isTerminalAgentFailure(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const response = error as { status?: unknown; data?: { code?: unknown } };
  if (response.status === 409 && response.data?.code === "DATABASE_UNAVAILABLE")
    return true;
  return (
    typeof response.status === "number" &&
    [409, 429, 502, 504].includes(response.status) &&
    typeof response.data?.code === "string" &&
    terminalCodes.has(response.data.code)
  );
}
