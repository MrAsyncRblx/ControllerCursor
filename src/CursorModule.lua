-- Gamepad Cursor
-- MrAsync


--[[
	About:
		It's hard enough for players to navigate UI using a gamepad.  It's harder for developers
		to implement meaningful mechanics to allow players to do this easier.  A solution for this
		problem is a GamepadCursor.  
		
		GamepadCursor produces a easy to under cursor controlled with the users thumbstick, like found
		in many AAA games such as Call of Duty and Destiny.
		
		Documentation is found below and the config is just below the documentation.

	Documentation:
		Public Methods
			void ShowCursor()
			void HideCursor()
	
		Private Methods
			void UpdateCursorPosition()
			
		Events
			void CursorActivated
			void CursorDeactivated
			
			Instance GuiObjectSelectionStarted
			Instance GuiObjectSelectionEnded
					
]]


--//	CONFIG	\\--

local CREATE_GUI = true 							--Auto creates GUI if set to true, if false, you must change the CursorGui and Cursor variables
local CURSOR_ICON = "rbxassetid://4883624920"		--Image of the cursor
local CURSOR_SIZE = UDim2.new(0, 15, 0, 15)			--Size in offset of the cursor

local SENSITIVITY = 10								--How fast the cursor will move
local SCROLL_SPEED = 1024							--How fast ScrollingFrames will scroll
local THUMBSTICK_DEADZONE = 0.5						--To prevent unnessesary moves caused by loose thumbstick.
local THUMBSTICK_KEY = Enum.KeyCode.Thumbstick1		--Enum of thumbstick that will be polled
local ACTIVATION_KEY = Enum.KeyCode.ButtonSelect	--Enum of button that will activate and deactivate cursor
local DEFAULT_GAMEPAD = Enum.UserInputType.Gamepad1	--Enum of the default gamepad

--Valid GUI object types that can be selected
local VALID_SELECTION_TYPES = {
    ["TextButton"] = true,
    ["ImageButton"] = true,
    ["TextBox"] = true,
    ["ScrollingFrame"] = true
}

--Vectors used to manage scrolling with the right stick
local GUI_VECTORS = {
	[Enum.ScrollingDirection.XY] = Vector2.new(1,1),
	[Enum.ScrollingDirection.X] = Vector2.new(1,0),
	[Enum.ScrollingDirection.Y] = Vector2.new(0,1),
}

--//	CONFIG END	\\--


local GamepadCursor = {}
local self = GamepadCursor

--//Player
local Player = game.Players.LocalPlayer

--//Services / Top Level
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local PlayerScripts = Player:WaitForChild("PlayerScripts")
local PlayerGui = Player:WaitForChild("PlayerGui")


--//Controllers
local PlayerModule = PlayerScripts:WaitForChild("PlayerModule")
local PlayerControl = require(PlayerModule:WaitForChild("ControlModule"))


--//Locals
local CursorGui
local Cursor

--Automatically creates the GUI if CREATE_GUI is true
if (CREATE_GUI) then
	CursorGui = Instance.new("ScreenGui")
	CursorGui.Parent = PlayerGui
	CursorGui.Name = "GamepadCursor"
	CursorGui.DisplayOrder = 999999999
	CursorGui.ResetOnSpawn = true
	CursorGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	
	Cursor = Instance.new("ImageLabel")
	Cursor.Parent = CursorGui
	Cursor.Visible = false
	Cursor.Name = "Cursor"
	Cursor.AnchorPoint = Vector2.new(0.5, 0.5)
	Cursor.BackgroundTransparency = 1
	Cursor.Size = CURSOR_SIZE
	Cursor.ZIndex = 999999999
	Cursor.Image = CURSOR_ICON
	Cursor.Selectable = false
else
	CursorGui = PlayerGui:WaitForChild("GamepadCursor")	--EDIT IF YOU SET CREATE_GUI TO FALSE!
	Cursor = CursorGui.Cursor	--EDIT THIS TOO		
end


local isInCursorMode = false
local currentPosition = UDim2.new(0, 0, 0, 0)
local currentMoveDirection = Vector2.new(0, 0)

--Localize all available inputs for gamepad
local states = {}
for _, state in pairs(UserInputService:GetGamepadState(DEFAULT_GAMEPAD)) do
	states[state.KeyCode] = state
end	

--//Bindable event setup
self.Events = {}
self.Events.CursorActivated = Instance.new("BindableEvent")
	self.CursorActivated = self.Events.CursorActivated.Event
self.Events.CursorDeactivated = Instance.new("BindableEvent")
	self.CursorDeactivated = self.Events.CursorDeactivated.Event
self.Events.GuiObjectSelectionStarted = Instance.new("BindableEvent")
	self.GuiObjectSelectionStarted = self.Events.GuiObjectSelectionStarted.Event
self.Events.GuiObjectSelectionEnded = Instance.new("BindableEvent")
	self.GuiObjectSelectionEnded = self.Events.GuiObjectSelectionEnded.Event


--[[
    Private Methods
]]


--//Updates the position of the Cursor
local function UpdateCursorPosition(dt)
	local leftThumbstick = states[THUMBSTICK_KEY]
		
    --Update move direction by polling position
    if (leftThumbstick.Position.Magnitude > THUMBSTICK_DEADZONE) then
        currentMoveDirection = (Vector2.new(leftThumbstick.Position.X, -leftThumbstick.Position.Y) * SENSITIVITY) / CursorGui.AbsoluteSize
    else
        currentMoveDirection = Vector2.new(0, 0)
    end

    --Construct a new UDim2 position
    currentPosition = currentPosition + UDim2.new(currentMoveDirection.X*(dt*60), 0, currentMoveDirection.Y*(dt*60), 0)

    --Constrain with screen bounds
    currentPosition = UDim2.new(math.clamp(currentPosition.X.Scale, 0, 1), 0, math.clamp(currentPosition.Y.Scale, 0, 1), 0)

    --Update position of Cursor
    Cursor.Position = currentPosition

    --Detect UI at cursor position
    local uiObjects = (PlayerGui:GetGuiObjectsAtPosition(Cursor.AbsolutePosition.X, Cursor.AbsolutePosition.Y) or {})

	--Selects the uppermost, valid object (in case of hidden valid objects)
    local topUiObject
	for _, uiObject in ipairs(uiObjects) do
		if (uiObject and (VALID_SELECTION_TYPES[uiObject.ClassName] and uiObject.Selectable)) then
			topUiObject = uiObject
			
			break
		end
	end

    --Update selectionObject if object exists and is a valid class type
    if (topUiObject) then
		--If hot-selecting ui objects, one after another, fire selection ended for old object
		--Fire selection started once
		if (GuiService.SelectedObject) then
			if (GuiService.SelectedObject ~= topUiObject) then
				self.Events.GuiObjectSelectionEnded:Fire(GuiService.SelectedObject)		
			else
				--Detect if UI object is child of a ScrollingFrame, if so, react to right thumbstick movement
				local frame = GuiService.SelectedObject:FindFirstAncestorWhichIsA("ScrollingFrame")
				if frame then
					local rightThumbstick = states[Enum.KeyCode.Thumbstick2]
					
					if (rightThumbstick.Position.Magnitude > THUMBSTICK_DEADZONE) then
				        currentMoveDirection = (Vector2.new(rightThumbstick.Position.X, -rightThumbstick.Position.Y) * SENSITIVITY) / CursorGui.AbsoluteSize
				    else
						currentMoveDirection = Vector2.new(0, 0)
					end
					
					frame.CanvasPosition = frame.CanvasPosition+(((currentMoveDirection*(dt*60))*SCROLL_SPEED)*GUI_VECTORS[frame.ScrollingDirection])
				end
			end
		else
			self.Events.GuiObjectSelectionStarted:Fire(topUiObject)
		end
	
        GuiService.SelectedObject = topUiObject
	else
		--If selected object exists, fire event
		if (GuiService.SelectedObject) then
			self.Events.GuiObjectSelectionEnded:Fire(GuiService.SelectedObject)
		end
	
        GuiService.SelectedObject = nil
    end
end


--[[
	Public Methods
]]

--//Shows the cursor, binds to renderStepped to allow cursor movement
function GamepadCursor:ShowCursor()
	isInCursorMode = true

    UserInputService.MouseIconEnabled = false 
    GuiService.GuiNavigationEnabled = false
    GuiService.AutoSelectGuiEnabled = false
    Cursor.Visible = true

	--Disables player movement while selection GUI
	GuiService.SelectedObject = nil
    PlayerControl:Disable()

	--Set position to center of scree for cleanliness
    currentPosition = UDim2.new(0.5, 0, 0.5, 0)

	--Fire event and bind UpdateCursorPosition method to renderStepped
	self.Events.CursorActivated:Fire()
    RunService:BindToRenderStep("CursorUpdate", 1, UpdateCursorPosition)
end


--//Hides the cursor, removes renderStepped bind
function GamepadCursor:HideCursor()
	isInCursorMode = false

    UserInputService.MouseIconEnabled = true
    GuiService.GuiNavigationEnabled = true
    GuiService.AutoSelectGuiEnabled = true
    Cursor.Visible = false

	--Deselects any selected object, enables player movement
    GuiService.SelectedObject = nil
    PlayerControl:Enable()

	--Fire event, Unbindes UpdateCursorPosition method from renderStepped
	self.Events.CursorDeactivated:Fire()
    RunService:UnbindFromRenderStep("CursorUpdate")
end


--[[
	Binds
]]

--Detect changes in user input state
UserInputService.InputBegan:Connect(function(inputObject)
    if (inputObject.KeyCode == ACTIVATION_KEY) then
        isInCursorMode = not isInCursorMode

		--Show or hide cursor depending on isInCursorMode
        if (isInCursorMode) then
            self:ShowCursor()     
        else
            self:HideCursor()
		end
	elseif (inputObject.KeyCode == Enum.KeyCode.ButtonR3) then
		if (isInCursorMode) then
			isInCursorMode = false

			self:HideCursor()
		end
    end
end)

--Hide cursor if input type is changed from GamePad
UserInputService.LastInputTypeChanged:Connect(function(lastInputType)
	if (lastInputType ~= Enum.UserInputType.Gamepad1 and isInCursorMode) then
		self:HideCursor()
	end
end)

UserInputService.MouseIconEnabled = true

return GamepadCursor