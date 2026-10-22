import { type Session } from "@agromax/contracts";
import { AgromaxClient } from "@agromax/contracts/client";
export const ORIGIN =
  (import.meta as unknown as { env: Record<string, string> }).env
    .VITE_API_ORIGIN || "http://localhost:8787";
export function readSession(): Session | null {
  try {
    const s = JSON.parse(sessionStorage.getItem("agromax.session") || "null");
    return s?.accessToken ? s : null;
  } catch {
    return null;
  }
}
export function saveSession(s: Session | null) {
  if (s) sessionStorage.setItem("agromax.session", JSON.stringify(s));
  else sessionStorage.removeItem("agromax.session");
}
export const apiFor = (s: Session | null) =>
  new AgromaxClient(ORIGIN, s?.accessToken);
export const date = (v: string) =>
  new Date(v).toLocaleDateString("ru-RU", { day: "numeric", month: "short" });
export const errorText = (e: unknown) =>
  e instanceof Error
    ? e.message
    : "Не удалось выполнить запрос. Попробуйте ещё раз.";
// Keep operation IDs for an identical retry, including after a network interruption.
export function operationId(key: string): string {
  const k = "agromax.op." + key;
  let id = sessionStorage.getItem(k);
  if (!id) {
    id = crypto.randomUUID();
    sessionStorage.setItem(k, id);
  }
  return id;
}
export function clearOperation(key: string) {
  sessionStorage.removeItem("agromax.op." + key);
}
