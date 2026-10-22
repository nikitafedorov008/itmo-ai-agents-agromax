import test from "node:test";
import assert from "node:assert/strict";
import { photoOperationKey } from "../src/photoUpload.ts";
const photo = (
  content: string,
  name = "leaf.jpg",
  type = "image/jpeg",
  lastModified = 1,
) => new File([content], name, { type, lastModified });
test("same selected bytes and metadata reuse upload key across retries and new File instances", async () => {
  assert.equal(
    await photoOperationKey("field-a", photo("image")),
    await photoOperationKey(
      "field-a",
      photo("image", "leaf.jpg", "image/jpeg", 999),
    ),
  );
});
test("changed bytes, filename, MIME, or field cannot reuse the previous upload operation", async () => {
  const original = await photoOperationKey("field-a", photo("image"));
  for (const candidate of [
    photoOperationKey("field-a", photo("changed")),
    photoOperationKey("field-a", photo("image", "other.jpg")),
    photoOperationKey("field-a", photo("image", "leaf.jpg", "image/png")),
    photoOperationKey("field-b", photo("image")),
  ])
    assert.notEqual(await candidate, original);
});
