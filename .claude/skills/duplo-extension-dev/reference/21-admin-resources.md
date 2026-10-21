# 21 — Admin-scoped resources (`AdminResourcesController`)

Every resource is **workspace-scoped** by default: it lives under a tenant's workspace, any member of that
workspace can use it, and it renders in AI DevOps. An **admin-scoped** resource is platform-wide configuration
that administrators manage: it has no workspace in its route, every row belongs to the system **Admin
Workspace**, access follows that workspace's permission-set grants, and it renders in AI Admin. Worked example:
[`samples/admin-settings`](../../../../samples/admin-settings).

> "Scope" means two things on this platform. **Extension scope** (this guide) is *workspace* or *admin*: where a
> resource lives and who manages it; the manifest key for it is `scope`. **Provider scopes** are credentials
> (AWS, Kubernetes, GitHub…) a workspace holds and a resource names in `spec.scopeIds`
> ([07-scope-credentials](07-scope-credentials.md)). Always say which one you mean.

> **Requires a host SDK that ships `AdminResourcesController`** (platform PR duplocloud-internal/duplo-ai-helpdesk#685)
> **and** a portal with admin extension routes/menus. Do not compare version numbers — the loader pins an
> extension to exactly the version the host reports. `scripts/build-extension.sh` probes the host's SDK bundle for
> the type and fails with a clear message when it is missing; without it the backend does not compile. On an older
> portal the backend works but the pages and menu do not appear.

## When to choose admin extension scope

| Choose **admin** when the resource… | Keep **workspace** (default) when it… |
|---|---|
| configures the platform itself, or a system every tenant shares (a VPN server, an SSO/identity integration, a licence or notification setting) | belongs to one tenant/team (a cluster, a database, a deployment) |
| is managed by administrators (and whoever they grant the Admin Workspace) | should be usable by workspace members |
| has exactly one owner — the platform | is created many times, once per workspace |

Ask this per resource in Phase 1. If unsure, it is workspace-scoped. An extension may mix both: one admin
resource and several workspace resources — the most common shape is a workspace resource that *consumes* an
admin one (see [Workspace resources that consume an admin resource](#workspace-resources-that-consume-an-admin-resource)).

## What changes (and what does not)

Only the **controller**, the **URLs** that point at it, and the **frontend extension scope** change. The entity,
spec, result, hooks and service are identical in shape, and the provisioning lifecycle is the same pipeline.

| Piece | Workspace | Admin |
|---|---|---|
| Controller base | `ResourcesController<T,TSpec,TResult>` | `AdminResourcesController<T,TSpec,TResult>` (`Duplo.Ai.DataManagement.Controllers.Admin.Resource`) |
| Controller `[Route]` | `v1/aiservicedesk/user/data/workspaces/{workspaceId}/environment/extensions/<seg>` | `v1/aiservicedesk/admin/data/environment/extensions/<seg>` |
| Access-node declaration | `[AccessControl(Parent = typeof(Workspace), ParentIdProperty = "OwnerWorkspaceId")]` | **the same** — mandatory; the node sits under the Admin Workspace |
| Access | workspace members (per their grants), and admins | administrators, plus any user granted the Admin Workspace (per verb) |
| `OwnerWorkspaceId` | the route's workspace | the system Admin Workspace, set by the platform (never sent by the frontend or skill) |
| FE service `base()` | `/v1/aiservicedesk/user/data/workspaces/${tenant}/environment/${REST_SEGMENT}` | `/v1/aiservicedesk/admin/data/environment/${REST_SEGMENT}` |
| FE `REMOTE_UserSession` | needed (reads the selected tenant) | not needed |
| Ticket lookup | `GET /v1/aiservicedesk/tickets/${tenant}/origin-context?…` | `GET <admin base>/{id}/ticket-status` → `ticketName` (no workspace id) |
| Manifest menu tree | no `scope` | `"scope": "admin"` on the **top-level** node |
| Manifest `frontend.routes[]` | no `scope` | `"scope": "admin"` on each route the admin tree links to |
| Mounted at | `/ai/suite/{tenant}/extensions/<seg>` | `/ai/suite/admin/extensions/<seg>` (behind the admin route guard) |
| Skill write-back `RES` | `…/user/data/workspaces/<ownerWorkspaceId>/environment/extensions/<seg>/<id>` | `…/admin/data/environment/extensions/<seg>/<id>` |
| Provider-scope credentials | the workspace's provider scopes | only provider scopes attached to the Admin Workspace **and** listed in `spec.scopeIds` |

The rest of the naming rules ([00-naming](00-naming.md)) still apply: `restSegment`, route `path` and menu
`relativeUrl` stay `extensions/<feature>-<resource>`; the collection stays `extension_<entity>`.

## Backend

```csharp
using Duplo.Ai.DataManagement.AccessControl;
using Duplo.Ai.DataManagement.Controllers.Admin.Resource;
using Duplo.Ai.Model;

[ApiController]
[Route("v1/aiservicedesk/admin/data/environment/extensions/admin-settings")]
[AccessControl(Parent = typeof(Workspace), ParentIdProperty = "OwnerWorkspaceId")]   // mandatory — see below
public class AdminSettingsController : AdminResourcesController<AdminSetting, AdminSettingSpec, AdminSettingResult>
{
    public AdminSettingsController(IEntityService<AdminSetting> service, ILogger<AdminSettingsController> logger)
        : base(service, logger) { }
}
```

- `AdminResourcesController` is a thin subclass of `ResourcesController`: it returns the Admin Workspace from
  `GetWorkspaceIdFromRoute()`, so create stamps the Admin Workspace as `OwnerWorkspaceId` and every
  read/update/delete checks ownership against it. Nothing in the extension (controller, frontend, skill) has to
  know that workspace's id. It re-declares the five actions that take a `workspaceId`
  parameter (`can-deprovision`, `deprovision`, `reconcile`, `ticket`, `ticket-status`) so they bind without one.
  You add the `[Route]` and the access-node declaration.
- **The access-node declaration is mandatory** — the same
  `[AccessControl(Parent = typeof(Workspace), ParentIdProperty = "OwnerWorkspaceId")]` a workspace controller
  carries ([18-access-control](18-access-control.md)). Access to an admin resource follows the **Admin
  Workspace's permission-set grants**: administrators pass, and so does any user whose permission sets grant the
  Admin Workspace (per verb, with the usual subtree cascade). The node is what those grants are evaluated
  against, so without it no verb could be checked. Two consequences:
  - The host **refuses to load** an admin controller whose entity is not a registered access node (the access
    registry rebuild fails with *"pinned to workspace '…' but serves no registered access node"* and the load is
    rolled back). The build gate fails such a controller before you get that far.
  - The resource appears in the permission-set editor under the Admin Workspace, so an administrator can delegate
    it (e.g. a "VPN operators" permission set) without making anyone an administrator.
- **No `[Authorize]` attribute is needed** — the base class carries the admin-route access policy, which also
  admits the resource's own provisioning token on its callback routes (below).
- **Do not override `GetWorkspaceIdFromRoute()` yourself** on a `ResourcesController`, and never put a workspace
  controller under `admin/…` — the build gate rejects both.
- **Parent → child:** the SDK has no admin variant of `ChildResourceController`, so an admin child controller
  applies the two overrides itself: `protected override string GetWorkspaceIdFromRoute() => Workspace.AdminWorkspaceId;`
  plus the five `[BindNever] string? workspaceId` action overrides copied from `AdminResourcesController`
  (`async` overrides are fine), on the route
  `v1/aiservicedesk/admin/data/environment/extensions/<parent-seg>/{parentId}/<child-seg>`. The build gate checks
  all six. The child carries its usual Pattern-B node declaration (`Parent = typeof(<ParentEntity>)`).
  **Limitation:** a child built this way carries no `IFixedWorkspaceMetadata` (only `AdminResourcesController`
  does), so the access policy keeps it **administrators-only** and hierarchical filtering never sees the Admin
  Workspace. A user granted the Admin Workspace can manage the parent but gets **403 on its children**. If
  delegated users must manage children, model them as a second top-level admin resource that references the
  parent by id, until the SDK ships an admin child base.
- Custom endpoints ([05-custom-actions](05-custom-actions.md)) go on the same controller and inherit the admin
  route and access rule.

## When code needs the Admin Workspace id

Only backend code that steps outside `AdminResourcesController`, and then through the SDK constant
`Workspace.AdminWorkspaceId`, never a literal:

- **An admin child controller**, because the SDK has no admin `ChildResourceController` (above).
- **A workspace-routed controller or service that reads admin-owned rows**: the read-only workspace view below,
  or a workspace resource that consumes an admin one (its `ValidateAsync` and its read-only picker endpoint, both
  in the sample). Its route resolves to the caller's workspace, so it must filter on
  `OwnerWorkspaceId == Workspace.AdminWorkspaceId` explicitly.

The frontend and the agent skills never need it: every admin route, `ticket-status` included, resolves the
workspace on the server.

## Provisioning

All four modes work. The service, hooks, `NoSkillsFallbackMode`, workers and `*DirectAsync` overrides are
unchanged ([03-base-classes](03-base-classes.md), [11-deprovisioning](11-deprovisioning.md)).

- **Agent mode.** The ticket is opened in the Admin Workspace. For a resource owned by the Admin Workspace the
  platform grants the scoped token on `*/aiservicedesk/admin/data/environment/*/{id}/status` and `…/{id}/results`
  instead of the workspace routes, so the skill **must** post to the admin route:
  ```bash
  ID=$(jq -r '.id' shared/<subtype>.json)
  RES="${DUPLO_BASE:-$DUPLO_HOST}/v1/aiservicedesk/admin/data/environment/extensions/<seg>/$ID"
  curl -fsS -X POST "$RES/status" -H "Authorization: Bearer $DUPLO_TOKEN" -H "Content-Type: application/json" \
    -d '{"status":"Processing","subStatus":"…"}'
  ```
  `GetAdditionalProvisioningTokenPatterns()` may not name an admin route (the platform rejects it), so the
  agent can reach nothing on the admin side beyond its own resource's callbacks.
- **Worker / Passthrough / No-provision** run inside the host and need no token.
- **Scope credentials.** The Admin Workspace has **no scopes**. If provisioning needs cloud or SaaS credentials,
  add the scope ids to the resource's own `spec.scopeIds` (an admin picks them on the add form); the agent then
  receives them as usual ([07-scope-credentials](07-scope-credentials.md)). Do not ask the developer to pick
  "test scopes from the workspace" for an admin resource.

## Frontend

```ts
// The service: no REMOTE_UserSession and no workspace id anywhere — the admin routes resolve the Admin
// Workspace server-side (AdminResourcesController), including the provisioning ticket.
const REST_SEGMENT = 'extensions/admin-settings';   // still == manifest restSegment (build gate)

private readonly http = inject<any>(REMOTE_DuploHttpClient as any);   // use-ng22: inject(), no ctor params
private base(): string { return `/v1/aiservicedesk/admin/data/environment/${REST_SEGMENT}`; }
ticketName(id: string): Observable<string | null> {                    // ticket-status → { ticketName, … }
  return this.http.get(`${this.base()}/${id}/ticket-status`).pipe(map((r: any) => (r?.data ?? r)?.ticketName ?? null));
}
```

```jsonc
// manifest.json → frontend: the admin tree and the route it links to both carry "scope": "admin"
"menus": [
  { "id": "duplo.examples.adminsettings-platform-settings", "title": "Platform Settings",
    "type": "collapsible-section", "matIcon": "cog-outline", "scope": "admin",
    "children": [
      { "id": "duplo.examples.adminsettings-platform-settings-admin-settings", "title": "Admin Settings",
        "type": "item", "matIcon": "tune-variant", "relativeUrl": "extensions/admin-settings", "order": 40 }
    ] }
],
"routes": [
  { "path": "extensions/admin-settings", "resourceType": "AdminSetting", "subType": "admin-setting", "scope": "admin" }
]
```

- `scope` is `"workspace"` (the default when omitted) or `"admin"`. On `menus[]` it is read **only on the
  top-level node**; the whole tree renders on that side. Admin trees merge into the AI Admin menu **by title**,
  the same way workspace trees merge into AI DevOps ([08-parent-child-and-menus](08-parent-child-and-menus.md)).
- Every admin menu link needs a `routes[]` entry with the same `path` **and** `"scope": "admin"`; the router
  mounts it under `suite/admin/<path>` behind the admin guard.
- An extension that surfaces on both sides declares two menu trees (one per scope) and routes for each.
- **Ticket links go to AI Admin:** `this.router.navigate(['/ai/suite/admin/tickets/chat', name])`. Never
  `/ai/service-desk/<workspaceId>/tickets/chat/<name>` with the Admin Workspace id: that route's
  `SubscriptionsGuard` only accepts workspaces in the user's workspace list, the Admin Workspace is hidden from
  it, so the page fails with *"The requested workspace / tenant is not available"*. Look the ticket up with the
  resource's own `GET <admin base>/{id}/ticket-status` (returns `ticketName`) — never `tickets/<workspaceId>/
  origin-context`, which would make the frontend name the Admin Workspace. Admin requests never carry a
  workspace id: the backend fills it in. Needs a portal with the AI Admin ticket page.

## Read-only workspace view (optional)

Admin rows are invisible to anyone without an Admin Workspace grant. When workspace members need to SEE what
administrators provisioned (a VPN endpoint, a maintenance banner), add a second, read-only surface on the
workspace side. `samples/admin-settings` ships one. It is **optional**, and it is a **deliberate platform-wide
disclosure**: it returns every Admin Workspace row of that type to any member of any workspace. Ship it only when
that is intended, and project only fields every tenant may see.

**Backend — a plain read controller beside the admin one:**
```csharp
[ApiController]
[Authorize]                                                   // REQUIRED — see below
[AccessControl("workspaceId", AnchorNode = "Workspace")]      // anchor only; declare no node
[Route("v1/aiservicedesk/user/data/workspaces/{workspaceId}/environment/extensions/admin-settings")]
public class AdminSettingsReadController : ControllerBase
{
    // inject IEntityService<AdminSetting>; GET   → FindAsync(e => e.OwnerWorkspaceId == Workspace.AdminWorkspaceId)
    //                                      GET {id} → GetByIdAsync, 404 unless owned by the Admin Workspace
}
```
- Derive from **`ControllerBase`**, never `ResourcesController`: the resource base adds the write endpoints and
  filters rows to the ROUTE workspace, while these rows all belong to the Admin Workspace.
- **`[Authorize]` is mandatory.** The host has no fallback policy, so a controller without it is anonymous.
  With it, the tenant policy admits only members of `{workspaceId}` (and admins). The build gate fails a
  `ControllerBase` controller that lacks it.
- `[AccessControl("workspaceId", AnchorNode = "Workspace")]` gates each action on the caller's grant for that
  workspace without declaring a node (only one controller may declare an entity's node).
- **Return a view model, not the entity.** Project only what members may see; drop secrets, faults, ticket data,
  and any result field that echoes a hidden spec field. The sample returns name + key + status, but not the value
  nor the summary (the skill writes it as `key = "value"`).
- Wrap results like the platform does: `ApiResponse<PagedResponse<TView>>.SuccessResult(…)` for the list,
  `ApiResponse<TView>.SuccessResult(…)` for one row (`Duplo.Ai.DataManagement.Models`).
- Same `extensions/<seg>` segment as the admin route: the prefixes differ, so they do not collide.

**Frontend — the same pages, read-only on the workspace side:**
- Add a workspace menu tree (no `scope`) and a route with the same `path` and no `scope`, next to the admin ones.
- The host stamps `scope` on each extension route, and the remote's routes inherit it:
  `route.snapshot.data['scope']` is `'admin'` in AI Admin and `'workspace'` in AI DevOps. The service picks
  its base URL from it per call (it is a root singleton, shared by both sides).
- In `workspace` scope hide Create/Edit/Track/Ask agent, the hidden fields' columns and tiles, and send a direct
  visit to `add`/`edit` back to the list. The provisioning ticket lives in the hidden Admin Workspace, so
  non-admins cannot open it anyway.

## Manifest notes

- Nothing in `resources[]` marks a resource as admin: the controller's route does. Keep the five type names and
  `archetype: "typed"`.
- There is no `registrar` field: the backend manifest model does not have one, and no manifest should carry it.
- `sdkVersion` is written in by the build from the host's `sdk-version`; the build also probes that SDK for
  `AdminResourcesController` (see the requirement at the top).

## Build gate

`scripts/build-extension.sh` fails the build when:
- a controller derives from `AdminResourcesController` but its route is not
  `v1/aiservicedesk/admin/data/environment/extensions/<…>`, or it has no `[AccessControl(…)]` node declaration;
- the host SDK has no `AdminResourcesController`;
- a `ResourcesController`/`ChildResourceController` uses an admin route — except a child controller that overrides
  `GetWorkspaceIdFromRoute()`, which must then sit under the admin prefix and override all five workspace actions;
- a `scope` value is not `workspace` or `admin`, or a non-top-level menu node sets `scope`;
- a menu link has no `routes[]` entry with the same path and the same scope;
- the backend has only admin-scoped controllers but no frontend file calls `/v1/aiservicedesk/admin/data/environment/…`.

It warns when such an extension's skills post to `…/user/data/workspaces/…`.

## Verify (local, admin token)

```bash
A=$DUPLO_BASE/v1/aiservicedesk/admin/data/environment/extensions/<seg>
curl -fsS -H "Authorization: Bearer $ADMIN_TOKEN" "$A"                                  # 200
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $NON_ADMIN_TOKEN" "$A" # 403 without an Admin Workspace grant
curl -fsS -X POST "$A" -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"<name>","spec":{…}}'
# GET $A/<id> → ownerWorkspaceId is the Admin Workspace (not your workspace); poll until status Complete
```
In the UI, the menu appears only in AI Admin (`/ai/suite/admin/extensions/<seg>`), never in AI DevOps.
