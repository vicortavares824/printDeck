# Implementation Plan — Shared/Global Cloud Inventory for SupplyHub (offline-first)

Goal: all devices share ONE cloud inventory (add/edit/delete on one device is visible on others after sync); the cloud always holds the data; the app works fully offline with local persistence across restarts and syncs up when the network returns. Today the inventory is partitioned per `device_id` on both sides — change it to a shared scope without breaking the HTTP contract or existing rows.

## Key exploration findings (ground truth)

- The LIVE backend is `cloud_api` run as `app/main:app` (FastAPI title "...telemetria, filamentos e jobs", v1.0.0). Confirmed against `https://printdeck-cloud.onrender.com/openapi.json`: it exposes `/api/supply/items`, `/api/supply/sync`, `/api/supply/items/{item_id}` plus telemetry/jobs. The supply router is `cloud_api/app/routers/supply.py` (prefix `/api/supply`), mounted by `cloud_api/app/main.py`.
- DISCREPANCY (flag, do not silently fix): `cloud_api/render.yaml` `startCommand` is `uvicorn src.main:app ...`, but the deployed OpenAPI matches `app/main:app`, not `src/main:app`. The `src/` app is a separate Clean-Architecture project whose `supply_hub_router` serves `/api/supply-hub/*` — a DIFFERENT feature (SKU/movements/auth) the Flutter client does NOT use. **Assumption:** the live service runs `app.main:app` regardless of what `render.yaml` currently says; we change `app/`, leave `src/` untouched, and add a note to the README about this mismatch so a future redeploy using `render.yaml` does not silently drop `/api/supply`. Do NOT touch the sibling `d:\Bekup\projetos\printDeck\backend\` project.
- Tables are created via `Base.metadata.create_all` in `app/main.py` lifespan (no Alembic for `app/`). `alembic/env.py` targets the `src/` Base only. So any `app/models/supply.py` change must work with plain `create_all` — do NOT add a migration for the `app/` model. Adding a NEW nullable/defaulted column to an existing table is NOT applied by `create_all` on an existing DB, so the design choice below avoids schema change.
- `CloudSupplyItem` (`app/models/supply.py`): `id` int pk, `device_id` str not-null indexed, `item_id` str not-null indexed, `title`, `description`, `quantity` Float, `is_bought` Bool, `updated_at` DateTime. Keeping the column avoids a destructive migration (per the design decision).
- Flutter client package name is `mobileraker`. The supply client uses `dio`, `hive`/`hive_flutter`, `hooks_riverpod`, `freezed`/`json_serializable`. `SupplyItem` is `@freezed` + `fromJson`/`toJson`, no Hive adapter.
- The exact local-persistence pattern to mirror is `lib/service/local_filament_stock_service.dart`: `static const boxName`, `_loadFromHive()` guarded by `Hive.isBoxOpen(boxName)` in the constructor, write on every mutation via `await Hive.openBox<String>(boxName)` + `box.put(id, json)` / `box.delete(id)`.
- App boxes are opened in `lib/app_setup.dart` `openBoxes()` (and deleted in `deleteBoxes()`); follow that exact `Future.wait([...])` style.
- The test `test/features/supply_hub/inventory_notifier_test.dart` constructs `InventoryNotifier()` with no args, expects it to start EMPTY and to behave synchronously in-memory (push is a no-op because `_apiService` is null). The constructor's Hive load MUST be guarded by `Hive.isBoxOpen` so the test (which never opens Hive) still starts empty and passes.
- No backend tests exist; no AGENTS.md / steering files.

## Verification commands (discovered)

- Backend (from `cloud_api/`): `python -m pip install -r requirements.txt` then import/compile `python -c "import app.main"` and a local SQLite smoke test with `uvicorn app.main:app` + curl of the three supply endpoints (default `DATABASE_URL=sqlite+aiosqlite:///./cloud_database.db`). `python -m py_compile app/routers/supply.py app/models/supply.py app/schemas/supply.py`.
- Flutter (from repo root): `flutter test test/features/supply_hub/inventory_notifier_test.dart` and `flutter analyze lib/features/supply_hub`.

---

## Backend — shared scope + per-item upsert

- [ ] 1. Introduce a fixed shared-scope constant and rewrite `/api/supply/sync` as a per-item UPSERT; make GET return the whole shared inventory and DELETE scope by `item_id` only.
      Decision: keep the `device_id` column (no schema migration — `create_all` can't alter an existing table), but write/read all rows under one constant scope value `SHARED_SCOPE = "__shared__"`. `device_id` in requests is accepted but ignored for scoping. `/sync` matches existing rows by `item_id` within `SHARED_SCOPE`: update `title/description/quantity/is_bought/updated_at` if present, else insert; it MUST NOT delete rows absent from the payload (remove the `delete(...).where(device_id==...)` bulk delete). GET `/items` returns all rows where `device_id == SHARED_SCOPE` (ignore the `device_id` query param for scoping but keep accepting it for contract stability). DELETE `/items/{item_id}` deletes by `item_id` within `SHARED_SCOPE` (keep accepting `device_id` param, do not scope by it). Add a comment stating last-write-wins by `updated_at` is acceptable for v1 and that `/sync` is per-item upsert and never bulk-deletes the shared scope.
      Files: `cloud_api/app/routers/supply.py` (and, if a one-time backfill of pre-existing rows to `SHARED_SCOPE` is wanted, do it lazily in `/sync`/GET rather than a migration — note it in a comment; do not write a migration).
      Verify: from `cloud_api/`, `python -m py_compile app/routers/supply.py`; then local smoke test — `uvicorn app.main:app --port 8000`, POST two items via `/api/supply/sync` from "device A" and "device B" and confirm GET `/api/supply/items?device_id=anything` returns BOTH; re-POST a subset and confirm the omitted item is NOT deleted; DELETE one `item_id` and confirm it is gone for all. Expected: shared list, no data loss on partial sync.

- [ ] 2. Update `README_API.md` to document the shared-scope supply contract and the `app.main:app` vs `render.yaml` mismatch.
      Decision: README currently documents the unrelated `/api/supply-hub/*` (the `src/` app). Add a section for the real client contract `/api/supply/{items,sync,items/{id}}`: shared global scope, per-item upsert, non-destructive sync, `x-api-key` auth, `device_id` accepted-but-ignored-for-scoping. Add a short note that the live service runs `app.main:app` and that `render.yaml`'s `startCommand` points at `src.main:app` (which does NOT serve `/api/supply`), so a redeploy must run `app.main:app` for the client to work.
      Files: `cloud_api/README_API.md`.
      Verify: manual read-through; confirm the three `/api/supply/*` endpoints and shared-scope semantics are documented and the startCommand mismatch is called out.

## Flutter — offline-first local persistence, lossless push, non-destructive merge

- [ ] 3. Add a persistent local Hive box for supply items and load it in the notifier constructor (mirror `local_filament_stock_service.dart`).
      Decision: box `supply_hub_items`, `Hive.openBox<String>('supply_hub_items')`, one `SupplyItem` per key = `item.id`, value = `jsonEncode(item.toJson())` (reuse existing `toJson`/`fromJson`, NO `@HiveType` adapter). Add `static const boxName = 'supply_hub_items'` and `_loadFromHive()` guarded by `Hive.isBoxOpen(boxName)` called from the `InventoryNotifier` constructor so the box is the source of truth and the list survives restart / works offline. The no-arg `InventoryNotifier()` used by the test stays empty because the box is not open under test.
      Files: `lib/features/supply_hub/application/inventory_notifier.dart`; `lib/app_setup.dart` (add `Hive.openBox<String>('supply_hub_items')` in `openBoxes()` and `Hive.deleteBoxFromDisk('supply_hub_items')` in `deleteBoxes()`).
      Verify: `flutter analyze lib/features/supply_hub` — no issues; `flutter test test/features/supply_hub/inventory_notifier_test.dart` — still passes (starts empty, in-memory mutations work).

- [ ] 4. Persist every mutation to the local box and add a per-item dirty/pending-sync marker; make `_pushToCloud` non-destructive on failure and surface failures non-blockingly.
      Decision: on `addItem`/`increment`/`decrement`/`toggleBought`/`removeItem`/`removeItemWithCloud`, write the local box BEFORE/independently of the network call (`box.put(id, json)` / `box.delete(id)`). Track unsynced changes with an in-box dirty set (e.g. a `__pending__` key holding a JSON list of item ids, or a `pending` box) so failed pushes retry on the next sync; on push failure keep local data and mark items pending instead of the empty catch. Expose a way for the UI to learn a push failed without blocking (e.g. a `syncError`/`pendingCount` the page can read) — keep it non-blocking and non-destructive. Fix the misleading comment at ~line 124 (replace "o dado fica salvo localmente" with an accurate statement now that local persistence exists and the item is marked pending for retry).
      Files: `lib/features/supply_hub/application/inventory_notifier.dart` (optionally a small `presentation/screens/supply_hub_page.dart` tweak to surface pending/errors non-blockingly).
      Verify: `flutter analyze lib/features/supply_hub`; `flutter test test/features/supply_hub/inventory_notifier_test.dart` — passes (push no-op under null api; dirty-tracking must not throw when box is closed).

- [ ] 5. Make `pullFromCloud` a non-destructive merge by `item_id` and persist the merged result; push pending-but-unsynced local items.
      Decision: replace `state = cloudItems`. Merge rule: for ids present in cloud, cloud is authoritative for already-synced items; NEVER drop a local item that was created offline and never successfully pushed (preserve local-only items and push them). Union by `item_id`; cloud wins for shared ids that are not locally pending, local-pending wins and is re-pushed. After a successful merge, persist the merged list to `supply_hub_items`, then attempt to push any still-pending items. Keep the red SnackBar on pull failure (`supply_hub_page.dart`) and keep local data intact when offline (no throw clears the box).
      Files: `lib/features/supply_hub/application/inventory_notifier.dart`; `lib/features/supply_hub/application/supply_api_service.dart` only if a push path needs adjusting to the shared-scope contract (contract shape is unchanged, so likely no client-call change needed — `device_id` is still sent and ignored server-side).
      Verify: `flutter analyze lib/features/supply_hub`; `flutter test test/features/supply_hub/inventory_notifier_test.dart` — passes.

- [ ] 6. Keep the test compiling and passing; add coverage for local-persistence behavior if feasible without opening real Hive, else guard.
      Decision: the no-arg constructor must still start empty and behave synchronously (guarded by `Hive.isBoxOpen`). If the constructor signature changes, update the test accordingly (prefer NOT changing it). Optionally add a test that initializes Hive to a temp dir and opens `supply_hub_items` in `setUp` to assert load-on-construct and write-on-mutation, guarded so CI without a temp dir still works.
      Files: `test/features/supply_hub/inventory_notifier_test.dart`.
      Verify: `flutter test test/features/supply_hub/inventory_notifier_test.dart` — all tests pass; `flutter analyze` clean.

## Integration

- [ ] 7. Cross-subsystem check: run the backend locally (SQLite), point a debug build or a scripted client at it, and confirm shared scope + offline behavior end to end.
      Decision: simulate two devices syncing to the shared scope and confirm each sees the other's items after pull; kill the network and confirm local box persists across a restart and that mutations re-push (pending flag clears) when the backend returns.
      Files: none (verification only).
      Verify: backend smoke test from step 1 plus `flutter test` green; manual two-device merge check.

## Notes / assumptions / gaps

- `render.yaml` points at `src.main:app`; the live server is `app.main:app`. We change `app/` per the authoritative task and document the mismatch in the README; we do NOT edit `render.yaml` unless the user asks, to avoid changing deploy behavior as a side effect of this task.
- Keeping the `device_id` column and using a constant `SHARED_SCOPE` avoids any schema migration, which is required because `app/` uses `create_all` (no Alembic for the `app/` model) and `create_all` won't alter existing tables.
- `quantity` crosses the wire as `double` and is read back via `toInt()` — unchanged (fine for small integers); not in scope to change the model's `int`.
- No `@HiveType` adapter and no `build_runner` run are needed (we reuse existing `toJson`/`fromJson` and do not change freezed/json annotations).
