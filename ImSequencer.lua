-- ImSequencer for imgui-luau. Port of ImSequencer.{h,cpp} from https://github.com/CedricGuillemet/ImGuizmo
-- (105e4fde45e4e74aae8973d98750820ef7aca7e2).
-- Usage (same as C++):
--   local ImSequencer = require(path.ImSequencer)(G)       -- G = the table returned by the ImGui module
--   ret, currentFrame, expanded, selectedEntry, firstFrame =
--       ImSequencer.Sequencer(sequence, currentFrame, expanded, selectedEntry, firstFrame, sequenceOptions)
-- [Port] pointer arguments are passed by value and returned after `ret` (pass nil for a C++ NULL pointer, it is
-- returned as nil). Item and type indices are 1-based; selectedEntry -1 = none.
-- [Port] SequenceInterface (C++ abstract struct) is any table with these methods:
--   required: GetFrameMin(), GetFrameMax(), GetItemCount(),
--             Get(index) -> start, end, type, color          (C++ Get(index, int** start, int** end, int* type, unsigned* color))
--             Set(index, start, end)                         ([Port] writes through C++'s int** start/end when a slot is dragged)
--   optional (upstream defaults): BeginEdit(index), EndEdit(), GetItemTypeCount() -> 0, GetItemTypeName(typeIndex) -> "",
--             GetItemLabel(index) -> "", GetCollapseFmt() -> "%d Frames / %d entries", Add(typeIndex), Del(index),
--             Duplicate(index), Copy(), Paste(), GetCustomHeight(index) -> 0, DoubleClick(index),
--             CustomDraw(index, draw_list, rc, legendRect, clippingRect, legendClippingRect),
--             CustomDrawCompact(index, draw_list, rc, clippingRect)            (rects are ImRect)
--   sequence.focused is set by Sequencer.
-- Like upstream, zoom/drag state is shared by every sequencer (C++ function statics).
-- Plain Lua 5.1 syntax so the same file loads on LÖVE (LuaJIT).
return function(G)
    local ImGui, ImVec2, ImRect = G.ImGui, G.ImVec2, G.ImRect
    local floor, ceil, abs, min_, max_ = math.floor, math.ceil, math.abs, math.min, math.max
    local FLT_EPSILON = 1.192092896e-07
    local band = bit32.band

    local ImSequencer = {}
    ImSequencer.SEQUENCER_EDIT_NONE = 0
    ImSequencer.SEQUENCER_EDIT_STARTEND = 2
    ImSequencer.SEQUENCER_CHANGE_FRAME = 8
    ImSequencer.SEQUENCER_ADD = 16
    ImSequencer.SEQUENCER_DEL = 32
    ImSequencer.SEQUENCER_COPYPASTE = 64
    ImSequencer.SEQUENCER_EDIT_ALL = 2 + 8
    local SEQUENCER_EDIT_STARTEND, SEQUENCER_CHANGE_FRAME, SEQUENCER_ADD, SEQUENCER_DEL, SEQUENCER_COPYPASTE = 2, 8, 16, 32, 64

    local function int(x) -- C (int) cast: truncation toward zero
        if x >= 0 then return floor(x) end
        return ceil(x)
    end
    local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

    -- optional interface methods with upstream defaults
    local function call(seq, name, default, ...)
        local f = seq[name]
        if f then return f(seq, ...) end
        return default
    end

    local function SequencerAddDelButton(draw_list, pos, add)
        if add == nil then add = true end
        local io = ImGui.GetIO()
        local btnRect = ImRect(pos, ImVec2(pos.x + 16, pos.y + 16))
        local overBtn = btnRect:Contains(io.MousePos)
        local containedClick = overBtn and btnRect:Contains(io.MouseClickedPos[0])
        local clickedBtn = containedClick and io.MouseReleased[0]
        local btnColor = overBtn and 0xAAEAFFAA or 0x77A3B2AA
        if containedClick and io.MouseDownDuration[0] > 0 then
            btnRect:Expand(2.0)
        end

        local midy = pos.y + 16 / 2 - 0.5
        local midx = pos.x + 16 / 2 - 0.5
        draw_list:AddRect(btnRect.Min, btnRect.Max, btnColor, 4)
        draw_list:AddLine(ImVec2(btnRect.Min.x + 3, midy), ImVec2(btnRect.Max.x - 3, midy), btnColor, 2)
        if add then
            draw_list:AddLine(ImVec2(midx, btnRect.Min.y + 3), ImVec2(midx, btnRect.Max.y - 3), btnColor, 2)
        end
        return clickedBtn
    end

    -- function statics
    local framePixelWidth = 10.0
    local framePixelWidthTarget = 10.0
    local movingEntry = -1
    local movingPos = -1
    local movingPart = -1
    local MovingScrollBar = false
    local MovingCurrentFrame = false
    local panningView = false
    local panningViewSource = ImVec2(0, 0)
    local panningViewFrame = 0
    local sizingRBar = false
    local sizingLBar = false
    local cursorWidth = 8.0
    local MinBarWidth = 44.0

    function ImSequencer.Sequencer(sequence, currentFrame, expanded, selectedEntry, firstFrame, sequenceOptions)
        local ret = false
        local io = ImGui.GetIO()
        local cx = int(io.MousePos.x)
        local cy = int(io.MousePos.y)
        local legendWidth = 200

        local delEntry = -1
        local dupEntry = -1
        local ItemHeight = 20

        local popupOpened = false
        local sequenceCount = sequence:GetItemCount()
        if sequenceCount == 0 then
            return false, currentFrame, expanded, selectedEntry, firstFrame
        end
        local FrameMin, FrameMax = sequence:GetFrameMin(), sequence:GetFrameMax()
        ImGui.BeginGroup()

        local draw_list = ImGui.GetWindowDrawList()
        local canvas_pos = ImGui.GetCursorScreenPos()       -- ImDrawList API uses screen coordinates!
        local canvas_size = ImGui.GetContentRegionAvail()   -- Resize canvas to what's available
        local firstFrameUsed = firstFrame or 0

        local controlHeight = sequenceCount * ItemHeight
        for i = 1, sequenceCount do
            controlHeight = controlHeight + int(call(sequence, "GetCustomHeight", 0, i))
        end
        local frameCount = max_(FrameMax - FrameMin, 1)

        local customDraws = {}
        local compactCustomDraws = {}
        -- zoom in/out
        local visibleFrameCount = floor((canvas_size.x - legendWidth) / framePixelWidth)
        local barWidthRatio = min_(visibleFrameCount / frameCount, 1.0)
        local barWidthInPixels = barWidthRatio * (canvas_size.x - legendWidth)


        if ImGui.IsWindowFocused() and io.KeyAlt and io.MouseDown[2] then
            if not panningView then
                panningViewSource = ImVec2(io.MousePos.x, io.MousePos.y)
                panningView = true
                panningViewFrame = firstFrame
            end
            firstFrame = panningViewFrame - int((io.MousePos.x - panningViewSource.x) / framePixelWidth)
            firstFrame = clamp(firstFrame, FrameMin, FrameMax - visibleFrameCount)
        end
        if panningView and not io.MouseDown[2] then
            panningView = false
        end
        framePixelWidthTarget = clamp(framePixelWidthTarget, 0.1, 50.0)

        framePixelWidth = framePixelWidth + (framePixelWidthTarget - framePixelWidth) * 0.33

        frameCount = FrameMax - FrameMin
        if visibleFrameCount >= frameCount and firstFrame then
            firstFrame = FrameMin
        end

        -- --
        if expanded ~= nil and not expanded then
            ImGui.InvisibleButton("canvas", ImVec2(canvas_size.x - canvas_pos.x, ItemHeight))
            draw_list:AddRectFilled(canvas_pos, ImVec2(canvas_size.x + canvas_pos.x, canvas_pos.y + ItemHeight), 0xFF3D3837, 0)
            local tmps = string.format(call(sequence, "GetCollapseFmt", "%d Frames / %d entries"), frameCount, sequenceCount)
            draw_list:AddText(ImVec2(canvas_pos.x + 26, canvas_pos.y + 2), 0xFFFFFFFF, tmps)
        else
            local hasScrollBar = true
            -- test scroll area
            local headerSize = ImVec2(canvas_size.x, ItemHeight)
            local scrollBarSize = ImVec2(canvas_size.x, 14.0)
            ImGui.InvisibleButton("topBar", headerSize)
            draw_list:AddRectFilled(canvas_pos, ImVec2(canvas_pos.x + headerSize.x, canvas_pos.y + headerSize.y), 0xFFFF0000, 0)
            local childFramePos = ImGui.GetCursorScreenPos()
            local childFrameSize = ImVec2(canvas_size.x, canvas_size.y - 8.0 - headerSize.y - (hasScrollBar and scrollBarSize.y or 0))
            local childFrameRect = ImRect(childFramePos, ImVec2(childFramePos.x + childFrameSize.x, childFramePos.y + childFrameSize.y))
            ImGui.PushStyleColor(G.ImGuiCol.FrameBg, 0)
            ImGui.BeginChild(889, childFrameSize, G.ImGuiChildFlags.FrameStyle)
            sequence.focused = ImGui.IsWindowFocused()
            ImGui.InvisibleButton("contentBar", ImVec2(canvas_size.x, controlHeight))
            local contentMin = ImGui.GetItemRectMin()
            local contentMax = ImGui.GetItemRectMax()
            local contentHeight = contentMax.y - contentMin.y

            -- full background
            draw_list:AddRectFilled(canvas_pos, ImVec2(canvas_pos.x + canvas_size.x, canvas_pos.y + canvas_size.y), 0xFF242424, 0)

            -- current frame top
            local topRect = ImRect(ImVec2(canvas_pos.x + legendWidth, canvas_pos.y), ImVec2(canvas_pos.x + canvas_size.x, canvas_pos.y + ItemHeight))

            if not MovingCurrentFrame and not MovingScrollBar and movingEntry == -1 and band(sequenceOptions, SEQUENCER_CHANGE_FRAME) ~= 0
                and currentFrame and currentFrame >= 0 and topRect:Contains(io.MousePos) and io.MouseDown[0] then
                MovingCurrentFrame = true
            end
            if MovingCurrentFrame then
                if frameCount ~= 0 then
                    currentFrame = int((io.MousePos.x - topRect.Min.x) / framePixelWidth) + firstFrameUsed
                    if currentFrame < FrameMin then currentFrame = FrameMin end
                    if currentFrame >= FrameMax then currentFrame = FrameMax end
                end
                if not io.MouseDown[0] then
                    MovingCurrentFrame = false
                end
            end

            -- header
            draw_list:AddRectFilled(canvas_pos, ImVec2(canvas_size.x + canvas_pos.x, canvas_pos.y + ItemHeight), 0xFF3D3837, 0)
            if band(sequenceOptions, SEQUENCER_ADD) ~= 0 then
                if SequencerAddDelButton(draw_list, ImVec2(canvas_pos.x + legendWidth - ItemHeight, canvas_pos.y + 2), true) then
                    ImGui.OpenPopup("addEntry")
                end

                if ImGui.BeginPopup("addEntry") then
                    for i = 1, call(sequence, "GetItemTypeCount", 0) do
                        if ImGui.Selectable(call(sequence, "GetItemTypeName", "", i)) then
                            call(sequence, "Add", nil, i)
                            selectedEntry = sequence:GetItemCount()
                        end
                    end
                    ImGui.EndPopup()
                    popupOpened = true
                end
            end

            -- header frame number and lines
            local modFrameCount = 10
            local frameStep = 1
            while (modFrameCount * framePixelWidth) < 150 do
                modFrameCount = modFrameCount * 2
                frameStep = frameStep * 2
            end
            local halfModFrameCount = int(modFrameCount / 2)

            local function drawLine(i, regionHeight)
                local baseIndex = ((i % modFrameCount) == 0) or (i == FrameMax or i == FrameMin)
                local halfIndex = (i % halfModFrameCount) == 0
                local px = int(canvas_pos.x) + int(i * framePixelWidth) + legendWidth - int(firstFrameUsed * framePixelWidth)
                local tiretStart = baseIndex and 4 or (halfIndex and 10 or 14)
                local tiretEnd = baseIndex and regionHeight or ItemHeight

                if px <= (canvas_size.x + canvas_pos.x) and px >= (canvas_pos.x + legendWidth) then
                    draw_list:AddLine(ImVec2(px, canvas_pos.y + tiretStart), ImVec2(px, canvas_pos.y + tiretEnd - 1), 0xFF606060, 1)
                    draw_list:AddLine(ImVec2(px, canvas_pos.y + ItemHeight), ImVec2(px, canvas_pos.y + regionHeight - 1), 0x30606060, 1)
                end

                if baseIndex and px > (canvas_pos.x + legendWidth) then
                    draw_list:AddText(ImVec2(px + 3.0, canvas_pos.y), 0xFFBBBBBB, tostring(i))
                end
            end

            local function drawLineContent(i, regionHeight)
                local px = int(canvas_pos.x) + int(i * framePixelWidth) + legendWidth - int(firstFrameUsed * framePixelWidth)
                local tiretStart = int(contentMin.y)
                local tiretEnd = int(contentMax.y)

                if px <= (canvas_size.x + canvas_pos.x) and px >= (canvas_pos.x + legendWidth) then
                    draw_list:AddLine(ImVec2(px, tiretStart), ImVec2(px, tiretEnd), 0x30606060, 1)
                end
            end
            for i = FrameMin, FrameMax, frameStep do
                drawLine(i, ItemHeight)
            end
            drawLine(FrameMin, ItemHeight)
            drawLine(FrameMax, ItemHeight)

            -- clip content
            draw_list:PushClipRect(childFrameRect.Min, childFrameRect.Max, true)

            -- draw item names in the legend rect on the left
            local customHeight = 0
            for i = 1, sequenceCount do
                local tpos = ImVec2(contentMin.x + 3, contentMin.y + (i - 1) * ItemHeight + 2 + customHeight)
                draw_list:AddText(tpos, 0xFFFFFFFF, call(sequence, "GetItemLabel", "", i))

                if band(sequenceOptions, SEQUENCER_DEL) ~= 0 then
                    if SequencerAddDelButton(draw_list, ImVec2(contentMin.x + legendWidth - ItemHeight + 2 - 10, tpos.y + 2), false) then
                        delEntry = i
                    end
                    if SequencerAddDelButton(draw_list, ImVec2(contentMin.x + legendWidth - ItemHeight - ItemHeight + 2 - 10, tpos.y + 2), true) then
                        dupEntry = i
                    end
                end
                customHeight = customHeight + call(sequence, "GetCustomHeight", 0, i)
            end

            -- slots background
            customHeight = 0
            for i = 1, sequenceCount do
                local col = ((i - 1) % 2 == 1) and 0xFF3A3636 or 0xFF413D3D

                local localCustomHeight = call(sequence, "GetCustomHeight", 0, i)
                local pos = ImVec2(contentMin.x + legendWidth, contentMin.y + ItemHeight * (i - 1) + 1 + customHeight)
                local sz = ImVec2(canvas_size.x + canvas_pos.x, pos.y + ItemHeight - 1 + localCustomHeight)
                if not popupOpened and cy >= pos.y and cy < pos.y + (ItemHeight + localCustomHeight) and movingEntry == -1
                    and cx > contentMin.x and cx < contentMin.x + canvas_size.x then
                    col = (col + 0x80201008) % 0x100000000
                    pos.x = pos.x - legendWidth
                end
                draw_list:AddRectFilled(pos, sz, col, 0)
                customHeight = customHeight + localCustomHeight
            end

            draw_list:PushClipRect(ImVec2(childFramePos.x + legendWidth, childFramePos.y), childFrameRect.Max, true)

            -- vertical frame lines in content area
            for i = FrameMin, FrameMax, frameStep do
                drawLineContent(i, int(contentHeight))
            end
            drawLineContent(FrameMin, int(contentHeight))
            drawLineContent(FrameMax, int(contentHeight))

            -- selection
            local selected = selectedEntry ~= nil and selectedEntry >= 1
            if selected then
                customHeight = 0
                for i = 1, selectedEntry - 1 do
                    customHeight = customHeight + call(sequence, "GetCustomHeight", 0, i)
                end
                draw_list:AddRectFilled(ImVec2(contentMin.x, contentMin.y + ItemHeight * (selectedEntry - 1) + customHeight),
                    ImVec2(contentMin.x + canvas_size.x, contentMin.y + ItemHeight * selectedEntry + customHeight), 0x801080FF, 1.0)
            end

            -- slots
            customHeight = 0
            for i = 1, sequenceCount do
                local start, end_, _, color = sequence:Get(i)
                local localCustomHeight = call(sequence, "GetCustomHeight", 0, i)

                local pos = ImVec2(contentMin.x + legendWidth - firstFrameUsed * framePixelWidth, contentMin.y + ItemHeight * (i - 1) + 1 + customHeight)
                local slotP1 = ImVec2(pos.x + start * framePixelWidth, pos.y + 2)
                local slotP2 = ImVec2(pos.x + end_ * framePixelWidth + framePixelWidth, pos.y + ItemHeight - 2)
                local slotP3 = ImVec2(pos.x + end_ * framePixelWidth + framePixelWidth, pos.y + ItemHeight - 2 + localCustomHeight)
                local slotColor = bit32.bor(color, 0xFF000000)
                local slotColorHalf = bit32.bor(band(color, 0xFFFFFF), 0x40000000)

                if slotP1.x <= (canvas_size.x + contentMin.x) and slotP2.x >= (contentMin.x + legendWidth) then
                    draw_list:AddRectFilled(slotP1, slotP3, slotColorHalf, 2)
                    draw_list:AddRectFilled(slotP1, slotP2, slotColor, 2)
                end
                if ImRect(slotP1, slotP2):Contains(io.MousePos) and io.MouseDoubleClicked[0] then
                    call(sequence, "DoubleClick", nil, i)
                end
                -- Ensure grabbable handles
                local max_handle_width = slotP2.x - slotP1.x / 3.0 -- (sic, upstream)
                local min_handle_width = min_(10.0, max_handle_width)
                local handle_width = clamp(framePixelWidth / 2.0, min_handle_width, max_handle_width)
                local rects = { ImRect(slotP1, ImVec2(slotP1.x + handle_width, slotP2.y)),
                    ImRect(ImVec2(slotP2.x - handle_width, slotP1.y), slotP2),
                    ImRect(slotP1, slotP2) }

                local quadColor = { 0xFFFFFFFF, 0xFFFFFFFF, (slotColor + (selected and 0 or 0x202020)) % 0x100000000 }
                if movingEntry == -1 and band(sequenceOptions, SEQUENCER_EDIT_STARTEND) ~= 0 then
                    for j = 3, 1, -1 do
                        local rc = rects[j]
                        if rc:Contains(io.MousePos) then
                            draw_list:AddRectFilled(rc.Min, rc.Max, quadColor[j], 2)
                        end
                    end

                    for j = 1, 3 do
                        local rc = rects[j]
                        if rc:Contains(io.MousePos) and childFrameRect:Contains(io.MousePos) then
                            if ImGui.IsMouseClicked(0) and not MovingScrollBar and not MovingCurrentFrame then
                                movingEntry = i
                                movingPos = cx
                                movingPart = j
                                call(sequence, "BeginEdit", nil, movingEntry)
                                break
                            end
                        end
                    end
                end

                -- custom draw
                if localCustomHeight > 0 then
                    local rp = ImVec2(canvas_pos.x, contentMin.y + ItemHeight * (i - 1) + 1 + customHeight)
                    local customRect = ImRect(ImVec2(rp.x + legendWidth - (firstFrameUsed - FrameMin - 0.5) * framePixelWidth, rp.y + ItemHeight),
                        ImVec2(rp.x + legendWidth + (FrameMax - firstFrameUsed - 0.5 + 2.0) * framePixelWidth, rp.y + localCustomHeight + ItemHeight))
                    local clippingRect = ImRect(ImVec2(rp.x + legendWidth, rp.y + ItemHeight), ImVec2(rp.x + canvas_size.x, rp.y + localCustomHeight + ItemHeight))

                    local legendRect = ImRect(ImVec2(rp.x, rp.y + ItemHeight), ImVec2(rp.x + legendWidth, rp.y + localCustomHeight))
                    local legendClippingRect = ImRect(ImVec2(canvas_pos.x, canvas_pos.y + ItemHeight), ImVec2(canvas_pos.x + legendWidth, canvas_pos.y + localCustomHeight + ItemHeight))
                    customDraws[#customDraws + 1] = { index = i, customRect = customRect, legendRect = legendRect, clippingRect = clippingRect, legendClippingRect = legendClippingRect }
                else
                    local rp = ImVec2(canvas_pos.x, contentMin.y + ItemHeight * (i - 1) + customHeight)
                    local customRect = ImRect(ImVec2(rp.x + legendWidth - (firstFrameUsed - FrameMin - 0.5) * framePixelWidth, rp.y),
                        ImVec2(rp.x + legendWidth + (FrameMax - firstFrameUsed - 0.5 + 2.0) * framePixelWidth, rp.y + ItemHeight))
                    local clippingRect = ImRect(ImVec2(rp.x + legendWidth, rp.y), ImVec2(rp.x + canvas_size.x, rp.y + ItemHeight))

                    compactCustomDraws[#compactCustomDraws + 1] = { index = i, customRect = customRect, legendRect = ImRect(), clippingRect = clippingRect, legendClippingRect = ImRect() }
                end
                customHeight = customHeight + localCustomHeight
            end

            -- moving
            if movingEntry >= 1 then
                ImGui.SetNextFrameWantCaptureMouse(true)
                local diffFrame = int((cx - movingPos) / framePixelWidth)
                if abs(diffFrame) > 0 then
                    local l, r = sequence:Get(movingEntry)
                    if selectedEntry then
                        selectedEntry = movingEntry
                    end
                    if band(movingPart, 1) ~= 0 then l = l + diffFrame end
                    if band(movingPart, 2) ~= 0 then r = r + diffFrame end
                    if l < 0 then
                        if band(movingPart, 2) ~= 0 then r = r - l end
                        l = 0
                    end
                    if band(movingPart, 1) ~= 0 and l > r then l = r end
                    if band(movingPart, 2) ~= 0 and r < l then r = l end
                    sequence:Set(movingEntry, l, r)
                    movingPos = movingPos + int(diffFrame * framePixelWidth)
                end
                if not io.MouseDown[0] then
                    -- single select
                    if diffFrame == 0 and movingPart ~= 0 and selectedEntry then
                        selectedEntry = movingEntry
                        ret = true
                    end

                    movingEntry = -1
                    call(sequence, "EndEdit", nil)
                end
            end

            -- cursor
            if currentFrame and firstFrame and currentFrame >= firstFrame and currentFrame <= FrameMax then
                local cursorOffset = contentMin.x + legendWidth + (currentFrame - firstFrameUsed) * framePixelWidth + framePixelWidth / 2 - cursorWidth * 0.5
                draw_list:AddLine(ImVec2(cursorOffset, canvas_pos.y), ImVec2(cursorOffset, contentMax.y), 0xA02A2AFF, cursorWidth)
                draw_list:AddText(ImVec2(cursorOffset + 10, canvas_pos.y + 2), 0xFF2A2AFF, tostring(currentFrame))
            end

            draw_list:PopClipRect()
            draw_list:PopClipRect()

            for _, customDraw in ipairs(customDraws) do
                call(sequence, "CustomDraw", nil, customDraw.index, draw_list, customDraw.customRect, customDraw.legendRect, customDraw.clippingRect, customDraw.legendClippingRect)
            end
            for _, customDraw in ipairs(compactCustomDraws) do
                call(sequence, "CustomDrawCompact", nil, customDraw.index, draw_list, customDraw.customRect, customDraw.clippingRect)
            end

            -- copy paste
            if band(sequenceOptions, SEQUENCER_COPYPASTE) ~= 0 then
                local rectCopy = ImRect(ImVec2(contentMin.x + 100, canvas_pos.y + 2), ImVec2(contentMin.x + 100 + 30, canvas_pos.y + ItemHeight - 2))
                local inRectCopy = rectCopy:Contains(io.MousePos)
                draw_list:AddText(rectCopy.Min, inRectCopy and 0xFF1080FF or 0xFF000000, "Copy")

                local rectPaste = ImRect(ImVec2(contentMin.x + 140, canvas_pos.y + 2), ImVec2(contentMin.x + 140 + 30, canvas_pos.y + ItemHeight - 2))
                local inRectPaste = rectPaste:Contains(io.MousePos)
                draw_list:AddText(rectPaste.Min, inRectPaste and 0xFF1080FF or 0xFF000000, "Paste")

                if inRectCopy and io.MouseReleased[0] then
                    call(sequence, "Copy", nil)
                end
                if inRectPaste and io.MouseReleased[0] then
                    call(sequence, "Paste", nil)
                end
            end

            ImGui.EndChild()
            ImGui.PopStyleColor()
            if hasScrollBar then
                ImGui.InvisibleButton("scrollBar", scrollBarSize)
                local scrollBarMin = ImGui.GetItemRectMin()
                local scrollBarMax = ImGui.GetItemRectMax()

                -- ratio = number of frames visible in control / number to total frames
                local startFrameOffset = ((firstFrameUsed - FrameMin) / frameCount) * (canvas_size.x - legendWidth)
                local scrollBarA = ImVec2(scrollBarMin.x + legendWidth, scrollBarMin.y - 2)
                local scrollBarB = ImVec2(scrollBarMin.x + canvas_size.x, scrollBarMax.y - 1)
                draw_list:AddRectFilled(scrollBarA, scrollBarB, 0xFF222222, 0)

                local inScrollBar = ImRect(scrollBarA, scrollBarB):Contains(io.MousePos)

                draw_list:AddRectFilled(scrollBarA, scrollBarB, 0xFF101010, 8)

                local scrollBarC = ImVec2(scrollBarMin.x + legendWidth + startFrameOffset, scrollBarMin.y)
                local scrollBarD = ImVec2(scrollBarMin.x + legendWidth + barWidthInPixels + startFrameOffset, scrollBarMax.y - 2)
                draw_list:AddRectFilled(scrollBarC, scrollBarD, (inScrollBar or MovingScrollBar) and 0xFF606060 or 0xFF505050, 6)

                local barHandleLeft = ImRect(scrollBarC, ImVec2(scrollBarC.x + 14, scrollBarD.y))
                local barHandleRight = ImRect(ImVec2(scrollBarD.x - 14, scrollBarC.y), scrollBarD)

                local onLeft = barHandleLeft:Contains(io.MousePos)
                local onRight = barHandleRight:Contains(io.MousePos)

                draw_list:AddRectFilled(barHandleLeft.Min, barHandleLeft.Max, (onLeft or sizingLBar) and 0xFFAAAAAA or 0xFF666666, 6)
                draw_list:AddRectFilled(barHandleRight.Min, barHandleRight.Max, (onRight or sizingRBar) and 0xFFAAAAAA or 0xFF666666, 6)

                local scrollBarThumb = ImRect(scrollBarC, scrollBarD)
                if sizingRBar then
                    if not io.MouseDown[0] then
                        sizingRBar = false
                    else
                        local barNewWidth = max_(barWidthInPixels + io.MouseDelta.x, MinBarWidth)
                        local barRatio = barNewWidth / barWidthInPixels
                        framePixelWidth = framePixelWidth / barRatio
                        framePixelWidthTarget = framePixelWidth
                        local newVisibleFrameCount = int((canvas_size.x - legendWidth) / framePixelWidthTarget)
                        local lastFrame = firstFrame + newVisibleFrameCount
                        if lastFrame > FrameMax then
                            framePixelWidth = (canvas_size.x - legendWidth) / (FrameMax - firstFrame)
                            framePixelWidthTarget = framePixelWidth
                        end
                    end
                elseif sizingLBar then
                    if not io.MouseDown[0] then
                        sizingLBar = false
                    else
                        if abs(io.MouseDelta.x) > FLT_EPSILON then
                            local barNewWidth = max_(barWidthInPixels - io.MouseDelta.x, MinBarWidth)
                            local barRatio = barNewWidth / barWidthInPixels
                            local previousFramePixelWidthTarget = framePixelWidthTarget
                            framePixelWidth = framePixelWidth / barRatio
                            framePixelWidthTarget = framePixelWidth
                            local newVisibleFrameCount = int(visibleFrameCount / barRatio)
                            local newFirstFrame = firstFrame + newVisibleFrameCount - visibleFrameCount
                            newFirstFrame = clamp(newFirstFrame, FrameMin, max_(FrameMax - visibleFrameCount, FrameMin))
                            if newFirstFrame == firstFrame then
                                framePixelWidth = previousFramePixelWidthTarget
                                framePixelWidthTarget = previousFramePixelWidthTarget
                            else
                                firstFrame = newFirstFrame
                            end
                        end
                    end
                else
                    if MovingScrollBar then
                        if not io.MouseDown[0] then
                            MovingScrollBar = false
                        else
                            local framesPerPixelInBar = barWidthInPixels / visibleFrameCount
                            firstFrame = int((io.MousePos.x - panningViewSource.x) / framesPerPixelInBar) - panningViewFrame
                            firstFrame = clamp(firstFrame, FrameMin, max_(FrameMax - visibleFrameCount, FrameMin))
                        end
                    else
                        if scrollBarThumb:Contains(io.MousePos) and ImGui.IsMouseClicked(0) and firstFrame and not MovingCurrentFrame and movingEntry == -1 then
                            MovingScrollBar = true
                            panningViewSource = ImVec2(io.MousePos.x, io.MousePos.y)
                            panningViewFrame = -firstFrame
                        end
                        if not sizingRBar and onRight and ImGui.IsMouseClicked(0) then
                            sizingRBar = true
                        end
                        if not sizingLBar and onLeft and ImGui.IsMouseClicked(0) then
                            sizingLBar = true
                        end
                    end
                end
            end
        end

        ImGui.EndGroup()

        -- (upstream: mouse wheel zoom over the region is #if 0'd out)

        if expanded ~= nil then
            if SequencerAddDelButton(draw_list, ImVec2(canvas_pos.x + 2, canvas_pos.y + 2), not expanded) then
                expanded = not expanded
            end
        end

        if delEntry ~= -1 then
            call(sequence, "Del", nil, delEntry)
            if selectedEntry and (selectedEntry == delEntry or selectedEntry > sequence:GetItemCount()) then
                selectedEntry = -1
            end
        end

        if dupEntry ~= -1 then
            call(sequence, "Duplicate", nil, dupEntry)
        end
        return ret, currentFrame, expanded, selectedEntry, firstFrame
    end

    return ImSequencer
end
