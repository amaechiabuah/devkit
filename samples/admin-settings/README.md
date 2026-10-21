# Admin Settings — an admin-scoped typed extension

The worked reference for an **admin-scoped** resource. It is the `helloworld` sample with one change of
scope: the resource is platform-wide configuration that only administrators see and manage, instead of a
per-workspace resource. Read `../helloworld/README.md` first; this file only covers what differs. The full
rules are in `.claude/skills/duplo-extension-dev/reference/21-admin-resources.md`.

```
backend/    Spec/Result/Resource/Hooks/Service (unchanged shape) + AdminSettingsController : AdminResourcesController
            + AdminSettingsReadController (read-only workspace view)
frontend/   Angular 22 Native-Federation remote (list/add/view) calling the ADMIN route; the service never reads the tenant
skills/     provision-adminsetting — reads settingKey+settingValue, writes summary back via the admin route
manifest.json  typed resource + skill + an admin-scoped menu tree and route ("scope": "admin")
```

## What differs from a workspace-scoped resource

| Piece | Workspace resource (`helloworld`) | Admin resource (this sample) |
|---|---|---|
| Controller base | `ResourcesController<…>` | `AdminResourcesController<…>` |
| Controller `[Route]` | `v1/aiservicedesk/user/data/workspaces/{workspaceId}/environment/extensions/helloworlds` | `v1/aiservicedesk/admin/data/environment/extensions/admin-settings` |
| Access-node declaration | `[AccessControl(Parent = typeof(Workspace), …)]` | the same — mandatory; the host rejects the load without it |
| Who can call it | members of the workspace (per their grants) | administrators, plus any user granted the Admin Workspace (per verb) |
| Row owner (`ownerWorkspaceId`) | the workspace in the route | always the system Admin Workspace, assigned by the platform |
| FE service base URL | `…/user/data/workspaces/${tenant}/environment/${REST_SEGMENT}` | `…/admin/data/environment/${REST_SEGMENT}` |
| FE list refresh | `session.getTenantRefreshTimer` (re-fetch on workspace switch) | `session.getRefreshTimer` (no workspace to switch) |
| Ticket link | `/ai/service-desk/<workspace>/tickets/chat/<name>` | `/ai/suite/admin/tickets/chat/<name>` |
| Manifest menu tree / route | no `scope` (workspace) | `"scope": "admin"` on the top-level menu node and on the route |
| Where it renders | AI DevOps, `/ai/suite/{tenant}/extensions/…` | AI Admin, `/ai/suite/admin/extensions/…` |
| Skill write-back `RES` | `…/user/data/workspaces/<ownerWorkspaceId>/environment/extensions/helloworlds/<id>` | `…/admin/data/environment/extensions/admin-settings/<id>` |
| Provider-scope credentials | the workspace's provider scopes | only scopes attached to the Admin Workspace and listed in `spec.scopeIds` |

**Read-only workspace view.** Workspace members can also see the settings — read-only, without the value —
under **AI DevOps → Platform Settings → Admin Settings**. `AdminSettingsReadController` (a plain
`ControllerBase` with `[Authorize]`) serves `GET`/`GET {id}` on
`…/user/data/workspaces/{workspaceId}/environment/extensions/admin-settings` and returns `AdminSettingView`
(name, key, status, timestamps). The same frontend pages read `scope` from the route and hide every action and
the value there. See `reference/21-admin-resources.md` → "Read-only workspace view".

Entity, spec, result, hooks and service are identical in shape. The provisioning lifecycle (tickets, status,
results, deprovision) is the same pipeline; the platform grants the agent's token on the admin callback routes.

## Requirements

- **A host SDK that ships `AdminResourcesController`** (duplo-ai-helpdesk#685). `build-extension.sh` probes the
  host's SDK bundle for it and stops with a clear error when it is missing.
- **A portal with admin extension routes, menus and the AI Admin ticket page** (`scope: "admin"` support). On
  an older portal the backend still works but the pages and menu do not appear.

## Build + load

```bash
./scripts/build-extension.sh  samples/admin-settings
./scripts/deploy-extension.sh samples/admin-settings/dist/extension.zip
```

## Verify

```bash
A=$DUPLO_BASE/v1/aiservicedesk/admin/data/environment/extensions/admin-settings
curl -fsS -H "Authorization: Bearer $ADMIN_TOKEN" "$A"                       # 200 for an administrator
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $USER_TOKEN" "$A"   # 403 without an Admin Workspace grant
curl -fsS -X POST "$A" -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"maintenance-banner","spec":{"settingKey":"maintenance-banner","settingValue":"Back at 18:00 UTC"}}'
# then poll GET $A/<id> until status is Complete; ownerWorkspaceId is the Admin Workspace, not yours
```

In the UI, **AI Admin → Platform Settings → Admin Settings** is the full editor; **AI DevOps → Platform Settings →
Admin Settings** is the read-only view (no value, no actions).
