# AGROMAX design QA

Source visual truth: `docs/design/selected-direction.png` (853 × 1844 px, approximately 2× density). User selected direction 3 plus the real map from direction 2. Native Flutter implementation and a desktop adaptation, not a flattened screenshot.

## Findings and comparison history

- [P2, fixed] Web answers occupied four narrow columns in a 560 px main region; long Russian options wrapped into six lines. Changed to a responsive grid with 220 px minimum columns. Post-fix evidence: `docs/design/qa/web-question.png` (two readable columns).
- [P2, fixed] Historical artifact actions remained after approval/version change. Web and mobile retain the old answer as history, hide stale clarification/task proposals and offer repeat inspection for approved records.
- [P2, fixed] Mobile density differed from the selected visual: photo and note stacked, followed by a tall map and duplicated full AI answer/evidence. Fixed with a 200 px paired hero, 140 px expandable map, concise artifact-body panel, two context tiles and expandable evidence. Post-fix native captures: `docs/design/qa/ios-workbench-native.jpg` and `docs/design/qa/ios-question-native.jpg`.

## Current rendered evidence

- `docs/design/qa/web-workbench.png`, `docs/design/qa/web-question.png`: Codex IAB, 901 × 988 CSS/pixel viewport, desktop layout, synthetic authenticated farm. Real MiMo answer and real uploaded demonstration image. Map imagery fetched from Esri; schema switch uses OSM. This desktop composition intentionally moves the map into a persistent left column.
- iPhone 17 Pro Simulator / iOS 26.4: real native build, Cupertino navigation/tab bars/dialogs. Actual screen captured in `docs/design/qa/ios-workbench-native.jpg` and `docs/design/qa/ios-question-native.jpg`. Native real-model option test passes.

## Required fidelity surfaces

- Typography: system fonts and native SF on iOS, strong title/body distinction; Russian options must wrap without truncation.
- Layout: desktop two-column adaptation approved by the brief; mobile must preserve the compact observation → map → AI → question hierarchy.
- Colors: ivory `#F7F8F1`, forest `#103F32`, sage and celery accents.
- Imagery: supplied AGROMAX logo retained; generated botanical asset is labelled as an illustration when no user photo exists. Actual map tiles, no fabricated satellite image. Private uploaded images remain protected.
- Copy: model-supplied questions/options; evidence reads appear only after actual tools. Confirmation remains a separate user action. No image-diagnosis claim.

## Interactions checked

IAB: authentication, real satellite/schema switch, weather with retrieval time, real model question → chosen answer → updated artifact, sources, explicit approval → linked task, repeat inspection saved as a linked draft. Console warnings/errors: none in final inspected session. API integration/security: 20 checks pass. Native photo/outbox/backend/SQLite test passes; native AI question → actual option → same conversation test passes on the final interaction code. The native weather tile was tapped and opened an actual five-day forecast.

## Implementation checklist

- [x] Web rendered and primary actions verified.
- [x] Both providers pass real two-turn workbench API checks.
- [x] Native photo/outbox integration passes.
- [x] Compact native density correction captured and compared with source.
- [x] Native real question/answer test passes and final app left running.

## Normalization and final comparison

The source and final implementation captures were opened together in one comparison input. Source 853 × 1844 px was normalized to 368 × 796 px (`docs/design/qa/reference-normalized.png`); native screenshots are 368 × 800 px exports of a 402 × 874 pt iPhone 17 Pro screen (native full-resolution test captures are 1206 × 2622 px, 3×). Native status/navigation/tab chrome is platform-owned and intentionally differs from the chrome-free concept. We compared app-owned regions: logo/selector/stages, paired photo/note, map peek, green evidence panel and question options. Readable native body text and 44 pt touch targets intentionally require scrolling; this is not a pixel-identical reproduction of the denser concept. Real model wording and zero/nonzero source counts vary with actual replies, rather than copying mock data.

Focused comparison: question controls (`ios-question-native.jpg`, `web-question.png`) against the question region in the normalized source. The previous narrow web options and unframed iOS options are corrected. Text wraps within controls, native tabs remain fixed, and no persistent control is hidden by horizontal overflow. The desktop viewport intentionally uses a separate 280 px map column.

Final fidelity review: system typography preserves the hierarchy with larger accessible native body sizes; 16/24 px corner radii and grouped spacing match the chosen direction; ivory/forest/celery colors are consistent; sharp botanical imagery and the supplied vector logo are retained; actual map tiles replace concept imagery with visible attribution. Copy describes actual observation evidence, real tool reads and explicit confirmation. The generic old observation text is expandable instead of being silently truncated without access.

## Functional review history

Independent review found and resolved cross-observation retry substitution, hiding of fresh approved-record questions, and loss of restored task proposals during web review. Pending mobile requests now require a dedicated explicit retry; clicking a new answer cannot resend the old message or allocate a new paid attempt. Stale proposals cannot prefill current approval. Native history/weather tiles invoke real app actions.

No actionable P0/P1/P2 findings remain. Remaining P3: format the secondary weather sheet into richer daily forecast rows; the current source, retrieval timestamp and values are available. Android runtime, physical camera/GPS permissions and cloud deployment remain outside the verified environment, as documented in `docs/VERIFICATION.md`.

final result: passed
