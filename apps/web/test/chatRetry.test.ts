import test from "node:test";
import assert from "node:assert/strict";
import { isTerminalAgentFailure } from "../src/chatRetry.ts";
const response = (status: number, code: string) =>
  Object.assign(new Error(code), { status, data: { code } });
test("does not authorize a fresh billable attempt for ambiguous network/in-progress failures", () => {
  for (const failure of [
    new TypeError("Failed to fetch"),
    response(409, "IN_PROGRESS"),
    response(503, "DATABASE_UNAVAILABLE"),
    response(429, "RATE_LIMIT"),
    response(503, "MODEL_UNCONFIGURED"),
    response(500, "INTERNAL"),
  ]) {
    assert.equal(isTerminalAgentFailure(failure), false);
  }
});
test("permits explicit new attempt after server confirms terminal provider or agent failure", () => {
  for (const failure of [
    response(504, "AGENT_TIMEOUT"),
    response(502, "PROVIDER_ERROR"),
    response(429, "PROVIDER_ERROR"),
    response(502, "INVALID_MODEL_OUTPUT"),
    response(409, "AGENT_TIMEOUT"),
    response(409, "RUN_INTERRUPTED"),
    response(409, "AGENT_FAILED"),
    response(502, "WEATHER_UNAVAILABLE"),
    response(409, "WEATHER_UNAVAILABLE"),
    response(409, "DATABASE_UNAVAILABLE"),
  ]) {
    assert.equal(isTerminalAgentFailure(failure), true);
  }
});
test("does not trust an unstructured or status-mismatched terminal-looking message", () => {
  for (const failure of [
    new Error("AGENT_TIMEOUT"),
    { data: { code: "AGENT_TIMEOUT" } },
    response(401, "AGENT_TIMEOUT"),
    null,
    undefined,
  ])
    assert.equal(isTerminalAgentFailure(failure), false);
});
