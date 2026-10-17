-- ImSequencer: upstream's example (MySequence with 5 items; double-click an item to expand it into an ImCurveEdit
-- RampEdit). Drag slots / their edges, scrub the frame in the header, zoom with the scrollbar handles,
-- +/- buttons add/delete/duplicate items.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local G = require(RS:WaitForChild("ImGui"))
local ImSequencer = require(RS:WaitForChild("ImSequencer"))(G)
local ImCurveEdit = require(RS:WaitForChild("ImCurveEdit"))(G)
local ImGui, ImVec2, ImRect = G.ImGui, G.ImVec2, G.ImRect

local SequencerItemTypeNames = { "Camera", "Music", "ScreenEffect", "FadeIn", "Animation" }

-- ImCurveEdit delegate (upstream RampEdit)
local RampEdit = {
	mPts = {
		{ ImVec2(-10, 0), ImVec2(20, 0.6), ImVec2(25, 0.2), ImVec2(70, 0.4), ImVec2(120, 1) },
		{ ImVec2(-50, 0.2), ImVec2(33, 0.7), ImVec2(80, 0.2), ImVec2(82, 0.8) },
		{ ImVec2(40, 0), ImVec2(60, 0.1), ImVec2(90, 0.82), ImVec2(150, 0.24), ImVec2(200, 0.34), ImVec2(250, 0.12) },
	},
	mbVisible = { true, true, true },
	mMin = ImVec2(0, 0),
	mMax = ImVec2(1, 1),
}
function RampEdit:GetCurveCount() return 3 end
function RampEdit:IsVisible(c) return self.mbVisible[c] end
function RampEdit:GetPointCount(c) return #self.mPts[c] end
function RampEdit:GetCurveColor(c) return ({ 0xFF0000FF, 0xFF00FF00, 0xFFFF0000 })[c] end
function RampEdit:GetPoints(c) return self.mPts[c] end
function RampEdit:GetCurveType(c) return ImCurveEdit.CurveSmooth end
function RampEdit:SortValues(c) table.sort(self.mPts[c], function(a, b) return a.x < b.x end) end
function RampEdit:EditPoint(c, p, value)
	self.mPts[c][p] = ImVec2(value.x, value.y)
	self:SortValues(c)
	for i, pt in self.mPts[c] do
		if pt.x == value.x then return i end
	end
	return p
end
function RampEdit:AddPoint(c, value)
	if #self.mPts[c] >= 8 then return end
	table.insert(self.mPts[c], value)
	self:SortValues(c)
end
function RampEdit:GetMax() return self.mMax end
function RampEdit:GetMin() return self.mMin end
function RampEdit:GetBackgroundColor() return 0 end

-- ImSequencer interface (upstream MySequence)
local MySequence = { mFrameMin = -100, mFrameMax = 1000, myItems = {} }
local function Item(type, s, e, expanded) return { mType = type, mFrameStart = s, mFrameEnd = e, mExpanded = expanded } end
MySequence.myItems = { Item(1, 10, 30, false), Item(2, 20, 30, true), Item(4, 12, 60, false), Item(3, 61, 90, false), Item(5, 90, 99, false) }
function MySequence:GetFrameMin() return self.mFrameMin end
function MySequence:GetFrameMax() return self.mFrameMax end
function MySequence:GetItemCount() return #self.myItems end
function MySequence:GetItemTypeCount() return #SequencerItemTypeNames end
function MySequence:GetItemTypeName(typeIndex) return SequencerItemTypeNames[typeIndex] end
function MySequence:GetItemLabel(index)
	return string.format("[%02d] %s", index - 1, SequencerItemTypeNames[self.myItems[index].mType])
end
function MySequence:Get(index)
	local item = self.myItems[index]
	return item.mFrameStart, item.mFrameEnd, item.mType, 0xFFAA8080 -- same color for everyone, return color based on type
end
function MySequence:Set(index, s, e)
	local item = self.myItems[index]
	item.mFrameStart, item.mFrameEnd = s, e
end
function MySequence:Add(type) table.insert(self.myItems, Item(type, 0, 10, false)) end
function MySequence:Del(index) table.remove(self.myItems, index) end
function MySequence:Duplicate(index) table.insert(self.myItems, table.clone(self.myItems[index])) end
function MySequence:GetCustomHeight(index) return self.myItems[index].mExpanded and 300 or 0 end
function MySequence:DoubleClick(index)
	if self.myItems[index].mExpanded then
		self.myItems[index].mExpanded = false
		return
	end
	for _, item in self.myItems do item.mExpanded = false end
	self.myItems[index].mExpanded = not self.myItems[index].mExpanded
end
local labels = { "Translation", "Rotation", "Scale" }
function MySequence:CustomDraw(index, draw_list, rc, legendRect, clippingRect, legendClippingRect)
	RampEdit.mMax = ImVec2(self.mFrameMax, 1)
	RampEdit.mMin = ImVec2(self.mFrameMin, 0)
	draw_list:PushClipRect(legendClippingRect.Min, legendClippingRect.Max, true)
	for i = 1, 3 do
		local pta = ImVec2(legendRect.Min.x + 30, legendRect.Min.y + (i - 1) * 14)
		local ptb = ImVec2(legendRect.Max.x, legendRect.Min.y + i * 14)
		draw_list:AddText(pta, RampEdit.mbVisible[i] and 0xFFFFFFFF or 0x80FFFFFF, labels[i])
		if ImRect(pta, ptb):Contains(ImGui.GetMousePos()) and ImGui.IsMouseClicked(0) then
			RampEdit.mbVisible[i] = not RampEdit.mbVisible[i]
		end
	end
	draw_list:PopClipRect()

	ImGui.SetCursorScreenPos(rc.Min)
	ImCurveEdit.Edit(RampEdit, ImVec2(rc.Max.x - rc.Min.x, rc.Max.y - rc.Min.y), 137 + index, clippingRect)
end
function MySequence:CustomDrawCompact(index, draw_list, rc, clippingRect)
	RampEdit.mMax = ImVec2(self.mFrameMax, 1)
	RampEdit.mMin = ImVec2(self.mFrameMin, 0)
	draw_list:PushClipRect(clippingRect.Min, clippingRect.Max, true)
	for i = 1, 3 do
		for _, pt in RampEdit.mPts[i] do
			local p = pt.x
			local item = self.myItems[index]
			if p >= item.mFrameStart and p <= item.mFrameEnd then
				local r = (p - self.mFrameMin) / (self.mFrameMax - self.mFrameMin)
				local x = rc.Min.x + (rc.Max.x - rc.Min.x) * r
				draw_list:AddLine(ImVec2(x, rc.Min.y + 6), ImVec2(x, rc.Max.y - 4), 0xAA000000, 4)
			end
		end
	end
	draw_list:PopClipRect()
end

local selectedEntry, firstFrame, expanded, currentFrame = -1, 0, true, 100
local S = ImSequencer
local options = bit32.bor(S.SEQUENCER_EDIT_STARTEND, S.SEQUENCER_ADD, S.SEQUENCER_DEL, S.SEQUENCER_COPYPASTE, S.SEQUENCER_CHANGE_FRAME)

ImGui.CreateContext()
G.ImGui_ImplRoblox.Init() -- defaults to LocalPlayer.PlayerGui
RunService.RenderStepped:Connect(function()
	G.ImGui_ImplRoblox.NewFrame()
	ImGui.NewFrame()
	ImGui.SetNextWindowSize(ImVec2(900, 600), G.ImGuiCond.FirstUseEver)
	ImGui.Begin("ImSequencer")
	ImGui.PushItemWidth(130)
	MySequence.mFrameMin = ImGui.InputInt("Frame Min", MySequence.mFrameMin)
	ImGui.SameLine()
	currentFrame = ImGui.InputInt("Frame ", currentFrame)
	ImGui.SameLine()
	MySequence.mFrameMax = ImGui.InputInt("Frame Max", MySequence.mFrameMax)
	ImGui.PopItemWidth()
	_, currentFrame, expanded, selectedEntry, firstFrame = ImSequencer.Sequencer(MySequence, currentFrame, expanded, selectedEntry, firstFrame, options)
	-- add a UI to edit that particular item
	if selectedEntry ~= -1 then
		local item = MySequence.myItems[selectedEntry]
		ImGui.Text("I am a %s, please edit me", SequencerItemTypeNames[item.mType])
	end
	ImGui.End()
	ImGui.Render()
	G.ImGui_ImplRoblox.RenderDrawData(ImGui.GetDrawData())
end)
