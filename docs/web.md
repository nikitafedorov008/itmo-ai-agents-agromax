# AGROMAX web

React / TypeScript / Vite application, `@agromax/web`. Start API on `http://localhost:8787`, then run `npm run dev:web` from the repository root. Vite listens on port 5173. `VITE_API_ORIGIN` may override the API origin at build time. Build with `npm run build -w @agromax/web`; typecheck with `npm run typecheck -w @agromax/web`.

Chief users can add a real field from the empty state or fields sidebar. Name, crop, area and center coordinates are required; polygon entry is optional. Point-only records are labeled as having no contour and rendered as map markers. Field creation requires explicit confirmation and uses an idempotent operation ID.

The UI uses shared `@agromax/contracts` types and `ApiClient`. No mock data or AI fallback is provided. The demo button requests a separate demo farm from the real API. Synthetic demo boundaries are explicitly marked on the map. Leaflet renders OpenStreetMap tiles; the field list provides keyboard-accessible field selection independently of map controls. External tiles and Google Fonts require network access; system fonts remain available.

Session tokens live in `sessionStorage` (tab lifetime), never in URLs, logs, or permanent localStorage. Logout unmounts the workspace and aborts active bootstrap, weather, chat and photo requests; bootstrap polling stops. Successful mutations reload server state. Private photos are fetched with the session bearer token, displayed using temporary object URLs and revoked on unmount.

Identical mutation retries reuse operation IDs in sessionStorage. Observation save creates a draft. Approval and optional task creation require a separate explicit checkbox and commit to the API together. Task completion requires a written outcome and explicit confirmation. Repeat inspection creates a new observation linked to the original. The app exposes persisted conversations, sources, artifacts, tasks, notifications and weather from the API. Unconfigured model or weather/API failures stay visible; nothing fabricates a response.

Desktop layout shows fields/map, assistant and context side by side. Mobile tabs switch these panels. Forms use native required validation, visible labels, keyboard focus states, loading and error states. All dates use Russian locale. Parent integration verification should exercise the rendered UI through Codex In-app Browser.
