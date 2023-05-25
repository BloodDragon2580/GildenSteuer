local AceGUI = LibStub("AceGUI-3.0")

MyMod_Settings = {
	MinimapPos = 45
}

function MyMod_MinimapButton_Reposition()
	MyMod_MinimapButton:SetPoint("TOPLEFT","Minimap","TOPLEFT",52-(80*cos(MyMod_Settings.MinimapPos)),(80*sin(MyMod_Settings.MinimapPos))-52)
end

function MyMod_MinimapButton_DraggingFrame_OnUpdate()

	local xpos,ypos = GetCursorPosition()
	local xmin,ymin = Minimap:GetLeft(), Minimap:GetBottom()

	xpos = xmin-xpos/UIParent:GetScale()+70
	ypos = ypos/UIParent:GetScale()-ymin-70

	MyMod_Settings.MinimapPos = math.deg(math.atan2(ypos,xpos))
	MyMod_MinimapButton_Reposition()
end

function MyMod_MinimapButton_OnClick()
	DEFAULT_CHAT_FRAME.editBox:SetText("/gt") 
	ChatEdit_SendText(DEFAULT_CHAT_FRAME.editBox, 0)
end
