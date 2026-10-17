-- Scrub the current frame in the header, drag a slot body (start+end move), drag a slot's right edge (end only),
-- click a slot to select it; empty sequences return early; Del via the "-" button clears the selection.
local RS = game:GetService("ReplicatedStorage")
local G = require(RS:WaitForChild("ImGui"))
local ImSequencer = require(RS:WaitForChild("ImSequencer"))(G)
local ImGui, ImVec2 = G.ImGui, G.ImVec2
local S = ImSequencer

ImGui.CreateContext()
G.ImGui_ImplRoblox.Init()
local io = ImGui.GetIO()

local Seq = { Items = { { s = 10, e = 20 }, { s = 30, e = 40 } }, Edits = 0, Open = 0 }
function Seq:GetFrameMin() return 0 end
function Seq:GetFrameMax() return 100 end
function Seq:GetItemCount() return #self.Items end
function Seq:Get(i) return self.Items[i].s, self.Items[i].e, 1, 0xFF8080AA end
function Seq:Set(i, s, e) self.Items[i].s, self.Items[i].e = s, e end
function Seq:BeginEdit() self.Open += 1 end
function Seq:EndEdit() self.Open -= 1 end
function Seq:Del(i) table.remove(self.Items, i) end

-- empty sequence: returns false and the values untouched
local empty = { GetFrameMin = function() return 0 end, GetFrameMax = function() return 10 end, GetItemCount = function() return 0 end }

local frame, done, origin = 0, false, nil
local ret, currentFrame, expanded, selectedEntry, firstFrame = false, 0, true, -1, 0
local opts = bit32.bor(S.SEQUENCER_EDIT_STARTEND, S.SEQUENCER_CHANGE_FRAME, S.SEQUENCER_DEL)
local fpw = 10 -- framePixelWidth (static default; firstFrame stays 0 since all frames fit)
local function frameX(f) return origin.x + 200 + f * fpw end
local function rowY(i) return origin.y + 20 + (i - 1) * 20 + 10 end -- header (20) + row center
game:GetService("RunService").Stepped:Connect(function()
	if done then return end
	frame += 1
	G.ImGui_ImplRoblox.NewFrame()
	io.DeltaTime = 1 / 60
	-- scrub: press in the header at frame 50
	if frame == 3 then io:AddMousePosEvent(frameX(50) + 2, origin.y + 10)
	elseif frame == 4 then io:AddMouseButtonEvent(0, true)
	elseif frame == 5 then io:AddMouseButtonEvent(0, false)
	-- drag item 1's body (frames 10..20) by +5 frames
	elseif frame == 8 then io:AddMousePosEvent(frameX(15), rowY(1))
	elseif frame == 9 then io:AddMouseButtonEvent(0, true)
	elseif frame == 10 then io:AddMousePosEvent(frameX(20), rowY(1))
	elseif frame == 11 then io:AddMouseButtonEvent(0, false)
	-- drag item 2's right edge (end 40, edge at frame 41) by +3 frames
	elseif frame == 14 then io:AddMousePosEvent(frameX(41) - 2, rowY(2))
	elseif frame == 15 then io:AddMouseButtonEvent(0, true)
	elseif frame == 16 then io:AddMousePosEvent(frameX(44) - 2, rowY(2))
	elseif frame == 17 then io:AddMouseButtonEvent(0, false)
	-- click item 1 without moving: selects it
	elseif frame == 20 then io:AddMousePosEvent(frameX(18), rowY(1))
	elseif frame == 21 then io:AddMouseButtonEvent(0, true)
	elseif frame == 22 then io:AddMouseButtonEvent(0, false)
	-- "-" (delete) button of item 1: legend x = 200 - 20 + 2 - 10 = 172
	elseif frame == 25 then io:AddMousePosEvent(origin.x + 172 + 8, origin.y + 20 + 2 + 2 + 8)
	elseif frame == 26 then io:AddMouseButtonEvent(0, true)
	elseif frame == 27 then io:AddMouseButtonEvent(0, false)
	end
	ImGui.NewFrame()
	ImGui.SetNextWindowPos(ImVec2(0, 0))
	ImGui.SetNextWindowSize(ImVec2(1300, 400))
	ImGui.Begin("Seq", nil, bit32.bor(G.ImGuiWindowFlags.NoMove, G.ImGuiWindowFlags.NoTitleBar))
	origin = ImGui.GetCursorScreenPos()
	local r = ImSequencer.Sequencer(empty, 5, true, 2, 0, opts)
	assert(r == false)
	ret, currentFrame, expanded, selectedEntry, firstFrame = ImSequencer.Sequencer(Seq, currentFrame, expanded, selectedEntry, firstFrame, opts)
	ImGui.End()
	ImGui.Render()
	G.ImGui_ImplRoblox.RenderDrawData(ImGui.GetDrawData())
	if frame == 5 then
		assert(currentFrame == 50, "scrub: currentFrame " .. currentFrame)
	elseif frame == 12 then
		assert(Seq.Items[1].s == 15 and Seq.Items[1].e == 25, ("body drag: %d..%d"):format(Seq.Items[1].s, Seq.Items[1].e))
		assert(selectedEntry == 1, "dragging did not select the item")
		assert(Seq.Open == 0, "BeginEdit/EndEdit unbalanced")
	elseif frame == 18 then
		assert(Seq.Items[2].s == 30 and Seq.Items[2].e == 43, ("edge drag: %d..%d"):format(Seq.Items[2].s, Seq.Items[2].e))
		assert(selectedEntry == 2)
	elseif frame == 22 then
		assert(ret == true and selectedEntry == 1, "click did not select item 1")
	elseif frame == 30 then
		done = true
		assert(#Seq.Items == 1 and Seq.Items[1].s == 30, "delete button did not remove item 1")
		assert(selectedEntry == -1, "selection not cleared after delete")
		assert(expanded == true and firstFrame == 0)
		print("OK")
	end
end)
