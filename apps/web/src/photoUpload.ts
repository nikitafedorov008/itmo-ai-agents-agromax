// The field UUID scopes deduplication to a tenant without placing tokens in keys.
// Include filename and MIME as they are part of the server's immutable Photo DTO.
export async function photoOperationKey(
  fieldId: string,
  file: File,
): Promise<string> {
  const bytes = await new Blob([
    JSON.stringify([file.name, file.type]) + "\0",
    file,
  ]).arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hash = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  return `photo:${fieldId}:${hash}`;
}
