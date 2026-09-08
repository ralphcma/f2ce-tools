# Embedded Map lifecycle repair

Mux removes a content definition and then recursively deletes its Geyser slot.
Previously F2CE only hid its embedded Mapper wrapper. That wrapper remained a
slot child, so Geyser's recursive deletion still called Mapper:type_delete(),
which calls closeMapWidget() even for an embedded mapper.

Each F2CE-created mapper now overrides only its own native deletion hook.
Release hides the native widget and deletes the wrapper, removing obsolete
Geyser references without closing the per-profile mapper. The global Mapper
class and other packages' mappers are unchanged. Map registration also reuses
its definition so repeated registration preserves singleton and timer state.
Remounting in a known room updates zoom/centering directly instead of replaying
the room handler and its arrival side effects.

`tests/map/content_lifecycle_run.lua` verifies removal followed by recursive
slot deletion, direct slot deletion, remounting, removal before the delayed
build, and repeat registration. These are offline checks of lifecycle calls;
they do not prove the Qt graphics layer renders correctly on every client.
The source and exact-package lifecycle tests passed under Lua 5.1. On a local
Mudlet 5.0.1 session, restoring an empty Map pane with the corrected script
produced a visible room/exits view and saved the Map tab successfully.

`scripts/build-map-fix.ps1` creates a local F2CE 3.3 package from an installed
build, replacing only the Map script and version metadata. This lets users
test the correction without installing unrelated work from this branch.
