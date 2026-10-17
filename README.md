# imsequencer-luau

Timeline/sequencer widget for imgui-luau: items as slots on a frame timeline, drag slots and their edges, scrub the
current frame, zoom/scroll with the scrollbar, add/delete/duplicate items, expandable rows with custom drawing.

Luau port of ImSequencer from [ImGuizmo](https://github.com/CedricGuillemet/ImGuizmo) for [imgui-luau](https://git.bug.tools/bug/imgui-luau) ([GitHub](https://github.com/4DBug/imgui-luau)).
Mirrors: [git.bug.tools](https://git.bug.tools/bug/imsequencer-luau) / [GitHub](https://github.com/4DBug/imsequencer-luau).
The example embeds [imcurveedit-luau](https://git.bug.tools/bug/imcurveedit-luau) in expanded rows, like upstream's.

## Usage

```lua
local G = require(ReplicatedStorage.ImGui)
local ImSequencer = require(ReplicatedStorage.ImSequencer)(G)

-- SequenceInterface (C++ ImSequencer::SequenceInterface): any table with these methods, indices 1-based
local Seq = { Items = { { s = 10, e = 30 }, { s = 20, e = 60 } } }
function Seq:GetFrameMin() return 0 end
function Seq:GetFrameMax() return 100 end
function Seq:GetItemCount() return #self.Items end
function Seq:Get(i) local it = self.Items[i]; return it.s, it.e, 1, 0xFFAA8080 end -- start, end, type, color
function Seq:Set(i, s, e) self.Items[i].s, self.Items[i].e = s, e end              -- [Port] see below
-- optional: GetItemLabel(i), GetItemTypeCount(), GetItemTypeName(t), Add(t), Del(i), Duplicate(i), Copy(), Paste(),
-- GetCustomHeight(i), DoubleClick(i), CustomDraw(...), CustomDrawCompact(...), BeginEdit(i), EndEdit(), GetCollapseFmt()

local currentFrame, expanded, selectedEntry, firstFrame = 0, true, -1, 0
local flags = bit32.bor(ImSequencer.SEQUENCER_EDIT_STARTEND, ImSequencer.SEQUENCER_CHANGE_FRAME)
-- each frame, inside a window:
local selected
selected, currentFrame, expanded, selectedEntry, firstFrame =
    ImSequencer.Sequencer(Seq, currentFrame, expanded, selectedEntry, firstFrame, flags)
```

`[Port]` differences:
- The pointer arguments (`int* currentFrame`, `bool* expanded`, `int* selectedEntry`, `int* firstFrame`) are passed by
  value and returned after the result; pass `nil` where C++ passes `NULL` (e.g. `expanded = nil` hides the expand button).
- `Get(index, int** start, int** end, int* type, unsigned* color)` becomes `Get(index) -> start, end, type, color`, and
  writes through the `int**` become a required `Set(index, start, end)`.
- Item and type indices are 1-based, `selectedEntry` `-1` = none. `CustomDraw`/`CustomDrawCompact` receive `ImRect`s.
- As upstream, zoom and drag state is shared by all sequencers (C++ function statics).

Full example (upstream's `MySequence` + `RampEdit`): `examples/roblox/main.client.luau`. The module is plain Lua 5.1 and also loads on LÖVE.

## Development

```sh
git clone --recursive https://git.bug.tools/bug/imsequencer-luau.git
bash tools/test.sh   # tests/t_*.luau in the core's Roblox mock + the Roblox example (uses tools/imcurveedit)
```

Upstream source (pinned) is in `tools/upstream/`; port-specific comments are tagged `[Port]`.

## License

MIT, see LICENSE (upstream copyright kept).
