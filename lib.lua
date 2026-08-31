--[[
	typeshit.cc - cozy ui library
	layout inspired by "rune" | colors, buttons & sliders inspired by toilet-ui

	api:
		local library = loadstring(<this file>)()
		library.flags / library.config_flags

		library:window{ name, size, menu_key }            -> window
		window:tab{ name }                                -> tab
		tab:section{ name, side = "left"|"right", fill }  -> section

		section:toggle{ name, flag, default, tooltip, callback }    -> toggle (chain :colorpicker / :keybind)
		section:slider{ name, flag, default, min, max, step, suffix, decimals, custom, tooltip, callback }
		section:dropdown{ name, flag, items, multi, default, tooltip, callback }
		section:button{ name, size = 1|0.5|0.33, tooltip, callback }
		section:textbox{ name, flag, placeholder, default, tooltip, callback }
		section:colorpicker{ name?, flag, color, transparency, tooltip, callback }
		section:keybind{ name?, flag, default, mode = "toggle"|"hold"|"always", tooltip, callback }
		section:listbox{ name?, flag, items, tooltip, callback }
		section:label{ name, color? }
		section:divider()

		library:notification{ text, time }
		library:save_config(name) / library:load_config(name) / library:get_configs()
		library:theme(name, color)          -- live theme editing
		library:toggle_menu()               -- menu keybind (default RightShift) or call directly
		library:unload()
]]

if getgenv and getgenv().typeshit and getgenv().typeshit.unload then
	getgenv().typeshit:unload()
end

-- executor backports
cloneref = cloneref or function(object)
	return object
end
gethui = gethui or function()
	return game:GetService("CoreGui")
end

--// services
local uis = game:GetService("UserInputService")
local players = game:GetService("Players")
local http_service = game:GetService("HttpService")
local gui_service = game:GetService("GuiService")
local tween_service = game:GetService("TweenService")
local coregui = cloneref(game:GetService("CoreGui"))

--// shortcuts
local vec2 = Vector2.new
local dim2 = UDim2.new
local dim = UDim.new
local rgb = Color3.fromRGB
local hex = Color3.fromHex
local hsv = Color3.fromHSV

local floor = math.floor
local clamp = math.clamp
local insert = table.insert
local remove = table.remove
local find = table.find

local camera = workspace.CurrentCamera
local lp = players.LocalPlayer
local mouse = lp:GetMouse()
local gui_inset = gui_service:GetGuiInset().Y

--// library
local library = {
	flags = {},
	config_flags = {},
	connections = {},
	instances = {},
	notifications = {},

	current_tab = nil,
	current_element_open = nil,
	keybind_listening = nil,

	open = true,
	gui = nil,

	directory = "typeshit",
	folders = { "/configs", "/fonts" },
	font = nil,
	text_size = 13,
}

-- theme registry (lets library:theme() recolor the whole ui live)
local theme_registry = {}

local function register_theme(instance, theme, property)
	theme_registry[theme] = theme_registry[theme] or {}
	insert(theme_registry[theme], { instance = instance, property = property })
end

-- toilet-core palette
library.theme = {
	["background"] = rgb(23, 23, 28), -- window body
	["outline"] = rgb(10, 10, 13), -- outer border / darkest
	["inline"] = rgb(52, 52, 62), -- strokes
	["contrast"] = rgb(29, 29, 35), -- panels / sidebar
	["element"] = rgb(44, 44, 53), -- buttons, dropdown boxes
	["element_hover"] = rgb(56, 56, 66),
	["text"] = rgb(232, 232, 238), -- bright text
	["muted_text"] = rgb(139, 139, 151), -- labels, values, unselected tabs
	["accent"] = rgb(86, 86, 255), -- indigo blue
	["slider_fill"] = rgb(197, 198, 209), -- light gray slider fill
}

function library:update_theme(theme, color)
	if not library.theme[theme] then
		return
	end

	library.theme[theme] = color

	for _, object in next, theme_registry[theme] or {} do
		if object.instance[object.property] ~= nil then
			object.instance[object.property] = color
		end
	end
end

function library:theme(name, color)
	library:update_theme(name, color)
end

--// key name map
local keys = {
	[Enum.KeyCode.LeftShift] = "LSHIFT",
	[Enum.KeyCode.RightShift] = "RSHIFT",
	[Enum.KeyCode.LeftControl] = "LCTRL",
	[Enum.KeyCode.RightControl] = "RCTRL",
	[Enum.KeyCode.LeftAlt] = "LALT",
	[Enum.KeyCode.RightAlt] = "RALT",
	[Enum.KeyCode.Insert] = "INS",
	[Enum.KeyCode.Backspace] = "BACK",
	[Enum.KeyCode.Return] = "ENTER",
	[Enum.KeyCode.CapsLock] = "CAPS",
	[Enum.KeyCode.Tab] = "TAB",
	[Enum.KeyCode.Escape] = "ESC",
	[Enum.KeyCode.Space] = "SPACE",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
	[Enum.KeyCode.Seven] = "7",
	[Enum.KeyCode.Eight] = "8",
	[Enum.KeyCode.Nine] = "9",
	[Enum.KeyCode.Zero] = "0",
	[Enum.KeyCode.KeypadOne] = "NUM1",
	[Enum.KeyCode.KeypadTwo] = "NUM2",
	[Enum.KeyCode.KeypadThree] = "NUM3",
	[Enum.KeyCode.KeypadFour] = "NUM4",
	[Enum.KeyCode.KeypadFive] = "NUM5",
	[Enum.KeyCode.KeypadSix] = "NUM6",
	[Enum.KeyCode.KeypadSeven] = "NUM7",
	[Enum.KeyCode.KeypadEight] = "NUM8",
	[Enum.KeyCode.KeypadNine] = "NUM9",
	[Enum.KeyCode.KeypadZero] = "NUM0",
	[Enum.KeyCode.Minus] = "-",
	[Enum.KeyCode.Equals] = "=",
	[Enum.KeyCode.LeftBracket] = "[",
	[Enum.KeyCode.RightBracket] = "]",
	[Enum.KeyCode.Semicolon] = ";",
	[Enum.KeyCode.Quote] = "'",
	[Enum.KeyCode.Comma] = ",",
	[Enum.KeyCode.Period] = ".",
	[Enum.KeyCode.Slash] = "/",
	[Enum.KeyCode.Backquote] = "`",
	[Enum.KeyCode.Up] = "UP",
	[Enum.KeyCode.Down] = "DOWN",
	[Enum.KeyCode.Left] = "LEFT",
	[Enum.KeyCode.Right] = "RIGHT",
	[Enum.KeyCode.Delete] = "DEL",
	[Enum.KeyCode.Home] = "HOME",
	[Enum.KeyCode.End] = "END",
	[Enum.KeyCode.PageUp] = "PGUP",
	[Enum.KeyCode.PageDown] = "PGDN",
	[Enum.UserInputType.MouseButton1] = "MB1",
	[Enum.UserInputType.MouseButton2] = "MB2",
	[Enum.UserInputType.MouseButton3] = "MB3",
}

for code = 1, 26 do
	local name = string.char(64 + code)
	local ok, enum = pcall(function()
		return Enum.KeyCode[name]
	end)
	if ok and enum then
		keys[enum] = name
	end
end

for code = 1, 12 do
	local ok, enum = pcall(function()
		return Enum.KeyCode["F" .. code]
	end)
	if ok and enum then
		keys[enum] = "F" .. code
	end
end

library.keys = keys

--// font (pixel font like the reference ui, falls back to a mono font)
local function load_font()
	local ok, font = pcall(function()
		local font_name = "SmallestPixel7"
		local font_path = library.directory .. "/fonts/main.ttf"
		local encoded_path = library.directory .. "/fonts/main_encoded.ttf"

		if writefile and isfile and not isfile(font_path) then
			writefile(font_path, game:HttpGet("https://github.com/i77lhm/storage/raw/refs/heads/main/fonts/fs-tahoma-8px.ttf"))
		end

		if writefile and isfile and not isfile(encoded_path) then
			local faces = {
				name = "SmallestPixel7",
				faces = {
					{
						name = "Regular",
						weight = 400,
						style = "normal",
						assetId = getcustomasset(font_path),
					},
				},
			}
			writefile(encoded_path, http_service:JSONEncode(faces))
		end

		return Font.new(getcustomasset(encoded_path), Enum.FontWeight.Regular)
	end)

	if ok and font then
		return font
	end

	return Font.fromEnum(Enum.Font.Code)
end

library.font = load_font()

--// helpers
function library:create(class, properties)
	local instance = new(class)

	for property, value in next, properties or {} do
		if property ~= "Parent" then
			instance[property] = value
		end
	end

	instance.Parent = properties and properties.Parent or nil

	if instance:IsA("Instance") then
		insert(library.instances, instance)
	end

	return instance
end

function library:corner(parent, radius)
	return library:create("UICorner", {
		Parent = parent,
		CornerRadius = dim(0, radius or 4),
	})
end

function library:stroke(parent, color, thickness, transparency)
	local stroke = library:create("UIStroke", {
		Parent = parent,
		Color = color or library.theme.outline,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Transparency = transparency or 0,
	})

	if color then
		for theme_name, theme_color in next, library.theme do
			if theme_color == color then
				register_theme(stroke, theme_name, "Color")
				break
			end
		end
	end

	return stroke
end

function library:padding(parent, left, right, top, bottom)
	return library:create("UIPadding", {
		Parent = parent,
		PaddingLeft = dim(0, left or 0),
		PaddingRight = dim(0, right or 0),
		PaddingTop = dim(0, top or 0),
		PaddingBottom = dim(0, bottom or 0),
	})
end

function library:list(parent, padding, direction, horizontal_align)
	return library:create("UIListLayout", {
		Parent = parent,
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = horizontal_align or Enum.HorizontalAlignment.Left,
		Padding = dim(0, padding or 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function library:connection(signal, callback)
	local connection = signal:Connect(callback)
	insert(library.connections, connection)
	return connection
end

function library:round(number, float)
	local multiplier = 1 / (float or 1)
	return floor(number * multiplier + 0.5) / multiplier
end

function library:tween(instance, time, properties)
	local tween = tween_service:Create(
		instance,
		TweenInfo.new(time or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		properties or {}
	)
	tween:Play()
	return tween
end

function library:tooltip(text)
	if not text or text == "" then
		return
	end

	local holder = library:create("Frame", {
		Parent = library.gui,
		Name = "tooltip",
		ZIndex = 200,
		Visible = false,
		BackgroundColor3 = library.theme.element,
		AutomaticSize = Enum.AutomaticSize.XY,
		BorderSizePixel = 0,
		BackgroundTransparency = 0,
	})

	library:corner(holder, 4)
	library:stroke(holder, library.theme.inline, 1)

	local label = library:create("TextLabel", {
		Parent = holder,
		Font = library.font,
		Text = text,
		TextSize = library.text_size,
		TextColor3 = library.theme.text,
		TextWrapped = true,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = dim2(0, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 200,
	})

	library:padding(holder, 6, 6, 4, 4)

	local maximum_width = 260
	task.defer(function()
		if label.AbsoluteSize.X > maximum_width then
			label.Size = dim2(0, maximum_width, 0, 0)
		end
	end)

	local move = library:connection(run_service.RenderStepped, function()
		local position = vec2(mouse.X, mouse.Y)
		holder.Position = dim2(0, position.X + 14, 0, position.Y + 14)

		local viewport = camera.ViewportSize
		if position.X + 14 + holder.AbsoluteSize.X > viewport.X then
			holder.Position = dim2(0, position.X - holder.AbsoluteSize.X - 10, 0, position.Y + 14)
		end
	end)

	library.active_tooltip = { holder = holder, move = move }
end

function library:remove_tooltip()
	local tooltip = library.active_tooltip

	if not tooltip then
		return
	end

	library.active_tooltip = nil
	tooltip.move:Disconnect()
	tooltip.holder:Destroy()
end

function library:hover_tooltip(instance, text)
	instance.MouseEnter:Connect(function()
		if library.keybind_listening then
			return
		end
		library:tooltip(text)
	end)

	instance.MouseLeave:Connect(function()
		library:remove_tooltip()
	end)
end

local run_service = game:GetService("RunService")

--// root gui
library.gui = library:create("ScreenGui", {
	Parent = gethui(),
	Name = "typeshit.cc",
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
})

-- mouse position helper (AbsolutePosition space)
local function get_mouse()
	return vec2(mouse.X, mouse.Y)
end

local function is_hovering(frame)
	local mouse_position = get_mouse()
	local position, size = frame.AbsolutePosition, frame.AbsoluteSize

	return mouse_position.X >= position.X
		and mouse_position.X <= position.X + size.X
		and mouse_position.Y >= position.Y
		and mouse_position.Y <= position.Y + size.Y
end

library.is_hovering = is_hovering

-- click-away: closes the open dropdown / colorpicker when clicking elsewhere
library:connection(uis.InputBegan, function(input, game_processed)
	if game_processed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local open_element = library.current_element_open

		if open_element and open_element.window then
			local inside_window = is_hovering(open_element.window)
			local inside_trigger = open_element.trigger and is_hovering(open_element.trigger)

			if not inside_window and not inside_trigger then
				open_element.set_visible(false)
				open_element.open = false
				library.current_element_open = nil
			end
		end
	end
end)

--// menu keybind
library.menu_key = Enum.KeyCode.RightShift

library:connection(uis.InputBegan, function(input, game_processed)
	if game_processed then
		return
	end

	if input.KeyCode == library.menu_key then
		if not library.keybind_listening then
			library:toggle_menu()
		end
	end
end)

function library:toggle_menu()
	local window = library.window

	if not window then
		return
	end

	library.open = not library.open

	if library.current_element_open then
		library.current_element_open.set_visible(false)
		library.current_element_open.open = false
		library.current_element_open = nil
	end

	library:remove_tooltip()

	local target = library.open and 0 or 1
	library:tween(window.holder, 0.22, { GroupTransparency = target })
	window.holder.Visible = true
end

function library:unload()
	library.gui:Destroy()

	for _, connection in next, library.connections do
		pcall(function()
			connection:Disconnect()
		end)
	end

	table.clear(library.connections)
	table.clear(library.instances)

	getgenv().typeshit = nil
end

--// notifications (top right, cozy slide-in)
function library:notification(properties)
	local cfg = {
		time = properties.time or properties.duration or 5,
		text = properties.text or properties.name or "notification",
	}

	local function refresh_notifications()
		for index, notification in next, library.notifications do
			library:tween(notification, 0.3, { Position = dim2(1, -14, 0, 14 + ((index - 1) * 34)) })
		end
	end

	local holder = library:create("Frame", {
		Parent = library.gui,
		Name = "notification",
		ZIndex = 150,
		AnchorPoint = vec2(1, 0),
		Position = dim2(1, -14, 0, 14 + (#library.notifications * 34)),
		Size = dim2(0, 0, 0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = library.theme.contrast,
		BorderSizePixel = 0,
	})

	library:corner(holder, 5)
	library:stroke(holder, library.theme.inline, 1)

	local accent = library:create("Frame", {
		Parent = holder,
		Position = dim2(0, 0, 0, 0),
		Size = dim2(0, 3, 1, 0),
		BackgroundColor3 = library.theme.accent,
		BorderSizePixel = 0,
		ZIndex = 151,
	})

	library:corner(accent, 5)
	register_theme(accent, "accent", "BackgroundColor3")

	local label = library:create("TextLabel", {
		Parent = holder,
		Font = library.font,
		Text = cfg.text,
		TextSize = library.text_size,
		TextColor3 = library.theme.text,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = dim2(0, 12, 0, 0),
		Size = dim2(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = 151,
	})

	library:padding(holder, 0, 14, 0, 0)

	insert(library.notifications, holder)

	task.delay(cfg.time, function()
		local index = find(library.notifications, holder)

		if index then
			remove(library.notifications, index)
		end

		library:tween(holder, 0.35, { BackgroundTransparency = 1 })
		library:tween(label, 0.3, { TextTransparency = 1 })
		library:tween(accent, 0.3, { BackgroundTransparency = 1 })

		local stroke = holder:FindFirstChildOfClass("UIStroke")

		if stroke then
			library:tween(stroke, 0.3, { Transparency = 1 })
		end

		refresh_notifications()
		task.wait(0.35)
		holder:Destroy()
	end)

	refresh_notifications()
end

--// window
function library:window(properties)
	local cfg = {
		name = properties.name or properties.Name or "typeshit.cc",
		size = properties.size or properties.Size or dim2(0, 580, 0, 420),
		menu_key = properties.menu_key or properties.MenuKey or Enum.KeyCode.RightShift,
		tabs = {},
	}

	library.menu_key = cfg.menu_key

	-- soft drop shadow
	local shadow = library:create("ImageLabel", {
		Parent = library.gui,
		Name = "shadow",
		ZIndex = 1,
		BackgroundTransparency = 1,
		Image = "http://www.roblox.com/asset/?id=6014261993",
		ImageColor3 = rgb(0, 0, 0),
		ImageTransparency = 0.45,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = rect(vec2(49, 49), vec2(450, 450)),
	})

	-- canvas group holder so we can fade the whole menu
	local holder = library:create("CanvasGroup", {
		Parent = library.gui,
		Name = "window",
		ZIndex = 2,
		GroupTransparency = 0,
		BorderSizePixel = 0,
	})

	cfg.holder = holder

	local main = library:create("Frame", {
		Parent = holder,
		Name = "main",
		Size = dim2(1, 0, 1, 0),
		BackgroundColor3 = library.theme.background,
		BorderSizePixel = 0,
	})

	library:corner(main, 8)
	register_theme(main, "background", "BackgroundColor3")

	local outline = library:stroke(main, library.theme.outline, 1)
	register_theme(outline, "outline", "Color")

	shadow.AnchorPoint = vec2(0.5, 0.5)
	shadow.Position = dim2(0.5, 0, 0.5, 4)

	local function apply_size(size)
		cfg.size = size
		holder.Size = size
		shadow.Size = dim2(0, size.X.Offset + 70, 0, size.Y.Offset + 70)
	end

	apply_size(cfg.size)
	holder.Position = dim2(0.5, -cfg.size.X.Offset / 2, 0.5, -cfg.size.Y.Offset / 2)
	library.window = cfg

	-- header
	local header = library:create("TextButton", {
		Parent = main,
		Name = "header",
		Size = dim2(1, 0, 0, 30),
		BackgroundColor3 = library.theme.background,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	})

	library:corner(header, 8)

	local header_accent = library:create("Frame", {
		Parent = header,
		Position = dim2(0, 10, 1, -5),
		Size = dim2(0, 4, 0, 4),
		BackgroundColor3 = library.theme.accent,
		BorderSizePixel = 0,
	})

	library:corner(header_accent, 2)
	register_theme(header_accent, "accent", "BackgroundColor3")

	local title = library:create("TextLabel", {
		Parent = header,
		Font = library.font,
		Text = cfg.name,
		TextSize = library.text_size,
		TextColor3 = library.theme.text,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = dim2(0, 22, 0, 0),
		Size = dim2(1, -60, 1, 0),
	})

	register_theme(title, "text", "TextColor3")

	-- minimize button
	local minimize = library:create("TextButton", {
		Parent = header,
		Font = library.font,
		Text = "-",
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		BackgroundTransparency = 1,
		AnchorPoint = vec2(1, 0.5),
		Position = dim2(1, -10, 0.5, 0),
		Size = dim2(0, 16, 0, 16),
	})

	minimize.MouseEnter:Connect(function()
		library:tween(minimize, 0.15, { TextColor3 = library.theme.text })
	end)

	minimize.MouseLeave:Connect(function()
		library:tween(minimize, 0.15, { TextColor3 = library.theme.muted_text })
	end)

	-- body
	local body = library:create("Frame", {
		Parent = main,
		Name = "body",
		Position = dim2(0, 0, 0, 26),
		Size = dim2(1, 0, 1, -26),
		BackgroundColor3 = library.theme.background,
		BorderSizePixel = 0,
	})

	register_theme(body, "background", "BackgroundColor3")

	-- sidebar (rune style: vertical tabs)
	local sidebar = library:create("Frame", {
		Parent = body,
		Name = "sidebar",
		Size = dim2(0, 108, 1, 0),
		BackgroundColor3 = library.theme.contrast,
		BorderSizePixel = 0,
	})

	library:corner(sidebar, 8)
	register_theme(sidebar, "contrast", "BackgroundColor3")
	library:padding(sidebar, 0, 0, 6, 6)
	library:list(sidebar, 2)

	-- content columns
	local content = library:create("Frame", {
		Parent = body,
		Name = "content",
		Position = dim2(0, 108, 0, 0),
		Size = dim2(1, -108, 1, 0),
		BackgroundTransparency = 1,
	})

	library:padding(content, 8, 8, 2, 8)

	local columns = library:create("Frame", {
		Parent = content,
		Size = dim2(1, 0, 1, 0),
		BackgroundTransparency = 1,
	})

	library:list(columns, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)

	cfg.header = header
	cfg.main = main
	cfg.body = body
	cfg.sidebar = sidebar
	cfg.columns = columns

	-- dragging
	local dragging, drag_start, start_position

	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			drag_start = input.Position
			start_position = holder.Position
		end
	end)

	library:connection(uis.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	-- resizing (bottom right grip)
	local grip = library:create("TextButton", {
		Parent = main,
		Text = "",
		BackgroundTransparency = 1,
		Position = dim2(1, -14, 1, -14),
		Size = dim2(0, 14, 0, 14),
		AutoButtonColor = false,
	})

	local resizing, resize_start, start_size
	start_size = cfg.size

	grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = true
			drag_start = input.Position
			start_size = dim2(0, main.AbsoluteSize.X, 0, main.AbsoluteSize.Y)
		end
	end)

	library:connection(uis.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = false
		end
	end)

	library:connection(uis.InputChanged, function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if dragging then
				local delta = input.Position - drag_start
				local viewport_size = camera.ViewportSize
				local x = clamp(start_position.X.Offset + delta.X, -main.Size.X.Offset + 130, viewport_size.X - 70)
				local y = clamp(start_position.Y.Offset + delta.Y, 0, viewport_size.Y - 42)

				holder.Position = dim2(0, x, 0, y)
			elseif resizing then
				local viewport_size = camera.ViewportSize
				local width = clamp(start_size.X.Offset + (input.Position.X - drag_start.X), 460, viewport_size.X)
				local height = clamp(start_size.Y.Offset + (input.Position.Y - drag_start.Y), 340, viewport_size.Y)

				apply_size(dim2(0, width, 0, height))
			end
		end
	end)

	-- minimize
	local minimized = false

	minimize.MouseButton1Click:Connect(function()
		minimized = not minimized

		if minimized then
			library:tween(body, 0.2, { Size = dim2(1, 0, 0, 0) })
			library:tween(holder, 0.2, { Size = dim2(0, main.Size.X.Offset, 0, 28) })
			shadow.Size = dim2(0, main.Size.X.Offset + 70, 0, 98)
		else
			library:tween(body, 0.2, { Size = dim2(1, 0, 1, -26) })
			library:tween(holder, 0.2, { Size = dim2(0, main.Size.X.Offset, 0, cfg.size.Y.Offset) })
			shadow.Size = dim2(0, main.Size.X.Offset + 70, 0, cfg.size.Y.Offset + 70)
		end
	end)

	function cfg.set_size(size)
		cfg.size = size
		apply_size(size)
	end


	return setmetatable(cfg, library)
end

--// tab (rune style: stacked sidebar buttons)
function library:tab(properties)
	local cfg = {
		name = properties.name or properties.Name or "tab",
		window = self,
	}

	local window = self

	-- sidebar button
	local button = library:create("TextButton", {
		Parent = window.sidebar,
		Font = library.font,
		Text = cfg.name,
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = dim2(1, 0, 0, 24),
		BackgroundColor3 = library.theme.contrast,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	})

	library:corner(button, 5)
	register_theme(button, "contrast", "BackgroundColor3")

	local indicator = library:create("Frame", {
		Parent = button,
		Position = dim2(0, 0, 0, 4),
		Size = dim2(0, 2, 1, -8),
		BackgroundColor3 = library.theme.accent,
		BorderSizePixel = 0,
		Visible = false,
	})

	library:corner(indicator, 2)
	register_theme(indicator, "accent", "BackgroundColor3")

	library:padding(button, 12, 6, 0, 0)

	-- tab page
	local page = library:create("Frame", {
		Parent = window.columns,
		Visible = false,
		Size = dim2(1, 0, 1, 0),
		BackgroundTransparency = 1,
	})

	library:list(page, 6, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)

	-- left / right scroll columns
	local left = library:create("ScrollingFrame", {
		Parent = page,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = dim2(0.5, -3, 1, 0),
		CanvasSize = dim2(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 1,
		ScrollBarImageColor3 = library.theme.inline,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})

	local right = library:create("ScrollingFrame", {
		Parent = page,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = false,
		Size = dim2(0.5, -3, 1, 0),
		CanvasSize = dim2(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 1,
		ScrollBarImageColor3 = library.theme.inline,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})

	cfg.buttons = { button = button, indicator = indicator, page = page }
	cfg.left = left
	cfg.right = right
	cfg.column_count = 0

	function cfg.open_tab()
		local current = library.current_tab

		if current then
			if current == cfg then
				return
			end

			current.buttons.button.TextColor3 = library.theme.muted_text
			current.buttons.indicator.Visible = false
			current.buttons.page.Visible = false
		end

		if library.current_element_open then
			library.current_element_open.set_visible(false)
			library.current_element_open.open = false
			library.current_element_open = nil
		end

		library.current_tab = cfg

		button.TextColor3 = library.theme.text
		indicator.Visible = true
		page.Visible = true
	end

	button.MouseButton1Click:Connect(function()
		cfg.open_tab()
	end)

	-- open first tab by default
	task.defer(function()
		if library.current_tab == nil then
			cfg.open_tab()
		end
	end)

	return setmetatable(cfg, library)
end

--// section
function library:section(properties)
	local cfg = {
		name = properties.name or properties.Name or "section",
		side = properties.side or properties.Side or "left",
		fill = properties.fill or properties.Fill,
		window = self,
	}

	local side = cfg.side == "right" and "right" or "left"

	if cfg.fill then
		self[side].Size = dim2(cfg.fill, -3, 1, 0)
	end

	self[side].Visible = true

	-- panel
	local panel = library:create("Frame", {
		Parent = self[side],
		Size = dim2(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = library.theme.contrast,
		BorderSizePixel = 0,
	})

	library:corner(panel, 6)
	register_theme(panel, "contrast", "BackgroundColor3")

	local panel_stroke = library:stroke(panel, library.theme.outline, 1)
	register_theme(panel_stroke, "outline", "Color")

	-- title
	local title = library:create("TextLabel", {
		Parent = panel,
		Font = library.font,
		Text = cfg.name,
		TextSize = library.text_size,
		TextColor3 = library.theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = dim2(0, 0, 0, 0),
		Size = dim2(1, 0, 0, 24),
		BackgroundTransparency = 1,
	})

	library:padding(title, 10, 10, 0, 0)
	register_theme(title, "text", "TextColor3")

	-- element holder
	local elements = library:create("Frame", {
		Parent = panel,
		Position = dim2(0, 0, 0, 22),
		Size = dim2(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})

	library:padding(elements, 8, 8, 2, 10)
	library:list(elements, 5)

	cfg.holder = elements
	cfg.panel = panel
	cfg.current_row = nil

	return setmetatable(cfg, library)
end

--// toggle
function library:toggle(properties)
	local cfg = {
		name = properties.name or properties.Name or "toggle",
		flag = properties.flag or properties.Flag or tostring(math.random(1000000, 9999999)),
		default = properties.default or properties.Default or false,
		callback = properties.callback or properties.Callback or function() end,
		tooltip = properties.tooltip or properties.Tooltip,
		section = self,
		right_count = 0,
	}

	local section = self

	-- row
	local row = library:create("TextButton", {
		Parent = section.holder,
		Size = dim2(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	})

	-- checkbox
	local checkbox = library:create("Frame", {
		Parent = row,
		Size = dim2(0, 11, 0, 11),
		Position = dim2(0, 0, 0.5, -5.5),
		BackgroundColor3 = library.theme.outline,
		BorderSizePixel = 0,
	})

	library:corner(checkbox, 3)

	local checkbox_stroke = library:stroke(checkbox, library.theme.inline, 1)
	register_theme(checkbox_stroke, "inline", "Color")

	local fill = library:create("Frame", {
		Parent = checkbox,
		Position = dim2(0, 2, 0, 2),
		Size = dim2(1, -4, 1, -4),
		BackgroundColor3 = library.theme.slider_fill,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})

	library:corner(fill, 2)
	register_theme(fill, "slider_fill", "BackgroundColor3")

	-- label
	local label = library:create("TextLabel", {
		Parent = row,
		Font = library.font,
		Text = cfg.name,
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = dim2(0, 18, 0, 0),
		Size = dim2(1, -24, 1, 0),
		BackgroundTransparency = 1,
	})

	register_theme(label, "muted_text", "TextColor3")

	-- right components (colorpickers / keybinds attach here)
	local right_components = library:create("Frame", {
		Parent = row,
		Position = dim2(1, -2, 0, 0),
		Size = dim2(0, 0, 1, 0),
		BackgroundTransparency = 1,
	})

	library:list(right_components, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Right)

	cfg.row = row
	cfg.checkbox = checkbox
	cfg.fill = fill
	cfg.label = label
	cfg.right_components = right_components

	function cfg.set(state, silent)
		cfg.state = state and true or false

		fill.BackgroundTransparency = cfg.state and 0 or 1
		label.TextColor3 = cfg.state and library.theme.text or library.theme.muted_text
		checkbox_stroke.Transparency = cfg.state and 0.35 or 0

		library.flags[cfg.flag] = cfg.state

		if not silent then
			cfg.callback(cfg.state)
		end
	end

	row.MouseButton1Click:Connect(function()
		cfg.set(not cfg.state)
	end)

	row.MouseEnter:Connect(function()
		if not cfg.state then
			library:tween(label, 0.12, { TextColor3 = library.theme.text })
		end
	end)

	row.MouseLeave:Connect(function()
		if not cfg.state then
			library:tween(label, 0.12, { TextColor3 = library.theme.muted_text })
		end
	end)

	if properties.tooltip or properties.Tooltip then
		library:hover_tooltip(row, properties.tooltip or properties.Tooltip)
	end

	cfg.set(cfg.default, true)

	library.config_flags[cfg.flag] = function(value)
		cfg.set(value, true)
		cfg.callback(value)
	end

	-- chained colorpicker
	function cfg.colorpicker(properties_override)
		local properties = properties_override or {}

		properties.parent_holder = right_components
		properties.inline = true
		properties.section = section

		return library:colorpicker(properties)
	end

	cfg.color_picker = cfg.colorpicker

	-- chained keybind
	function cfg.keybind(properties_override)
		local properties = properties_override or {}

		properties.chained = true
		properties.section = section
		properties.parent_holder = right_components

		return library:keybind(properties)
	end

	return setmetatable(cfg, library)
end

--// slider (toilet style: label left, value right, thin light-gray fill)
function library:slider(properties)
	local cfg = {
		name = properties.name or properties.Name or "slider",
		flag = properties.flag or properties.Flag or tostring(math.random(1000000, 9999999)),
		default = properties.default or properties.Default,
		min = properties.min or properties.Minimum or 0,
		max = properties.max or properties.Maximum or 100,
		step = properties.step or properties.increment or properties.interval or 1,
		suffix = properties.suffix or properties.Suffix or "",
		decimals = properties.decimals or properties.Decimals,
		custom = properties.custom or properties.Custom or nil,
		callback = properties.callback or properties.Callback or function() end,
		tooltip = properties.tooltip or properties.Tooltip,
		section = self,
		dragging = false,
	}

	if cfg.default == nil then
		cfg.default = cfg.min
	end

	local section = self

	-- outer
	local outer = library:create("Frame", {
		Parent = section.holder,
		Size = dim2(1, 0, 0, 26),
		BackgroundTransparency = 1,
	})

	-- label row: name left, value right
	local label = library:create("TextLabel", {
		Parent = outer,
		Font = library.font,
		Text = cfg.name,
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = dim2(0, 0, 0, 0),
		Size = dim2(1, 0, 0, 13),
		BackgroundTransparency = 1,
	})

	register_theme(label, "muted_text", "TextColor3")

	local value_label = library:create("TextLabel", {
		Parent = outer,
		Font = library.font,
		Text = "",
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = dim2(0, 0, 0, 0),
		Size = dim2(1, 0, 0, 13),
		BackgroundTransparency = 1,
	})

	register_theme(value_label, "muted_text", "TextColor3")

	-- track
	local track = library:create("TextButton", {
		Parent = outer,
		Position = dim2(0, 0, 0, 18),
		Size = dim2(1, 0, 0, 6),
		BackgroundColor3 = library.theme.outline,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	})

	library:corner(track, 3)
	register_theme(track, "outline", "BackgroundColor3")

	local track_stroke = library:stroke(track, library.theme.inline, 1)
	track_stroke.Transparency = 0.5
	register_theme(track_stroke, "inline", "Color")

	local progress = library:create("Frame", {
		Parent = track,
		Size = dim2(0, 0, 1, 0),
		BackgroundColor3 = library.theme.slider_fill,
		BorderSizePixel = 0,
	})

	library:corner(progress, 3)
	register_theme(progress, "slider_fill", "BackgroundColor3")

	local knob = library:create("Frame", {
		Parent = progress,
		AnchorPoint = vec2(1, 0.5),
		Position = dim2(1, 0, 0.5, 0),
		Size = dim2(0, 2, 0, 8),
		BackgroundColor3 = library.theme.text,
		BorderSizePixel = 0,
	})

	library:corner(knob, 1)
	register_theme(knob, "text", "BackgroundColor3")

	cfg.track = track
	cfg.progress = progress
	cfg.label = label
	cfg.value_label = value_label

	local function format_value(value)
		local text = tostring(cfg.custom and cfg.custom[tostring(value)] or value)

		if cfg.decimals then
			text = string.format("%." .. cfg.decimals .. "f", cfg.value)
			text = tostring(cfg.custom and cfg.custom[text] or text)
		end

		return text .. cfg.suffix
	end

	function cfg.set(value, silent)
		if type(value) ~= "number" then
			return
		end

		cfg.value = clamp(library:round(value, cfg.step), cfg.min, cfg.max)

		local alpha = (cfg.value - cfg.min) / (cfg.max - cfg.min)
		progress.Size = dim2(alpha, 0, 1, 0)
		value_label.Text = format_value(cfg.value)

		library.flags[cfg.flag] = cfg.value

		if not silent then
			cfg.callback(cfg.value)
		end
	end

	track.MouseButton1Down:Connect(function()
		cfg.dragging = true
		value_label.TextColor3 = library.theme.text

		local size_x = clamp((get_mouse().X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		cfg.set(((cfg.max - cfg.min) * size_x) + cfg.min)
	end)

	library:connection(uis.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			cfg.dragging = false
			value_label.TextColor3 = library.theme.muted_text
		end
	end)

	library:connection(uis.InputChanged, function(input)
		if cfg.dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local size_x = clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			cfg.set(((cfg.max - cfg.min) * size_x) + cfg.min)
		end
	end)

	-- fine tune with mouse wheel while hovering
	track.MouseEnter:Connect(function()
		cfg.mouse_over = true
	end)

	track.MouseLeave:Connect(function()
		cfg.mouse_over = false
	end)

	library:connection(uis.InputChanged, function(input)
		if cfg.mouse_over and input.UserInputType == Enum.UserInputType.MouseWheel then
			cfg.set(cfg.value + (input.Position.Z > 0 and cfg.step or -cfg.step))
		end
	end)

	if properties.tooltip or properties.Tooltip then
		library:hover_tooltip(outer, properties.tooltip or properties.Tooltip)
	end

	cfg.set(cfg.default, true)

	library.config_flags[cfg.flag] = function(value)
		cfg.set(value, true)
		cfg.callback(value)
	end

	return setmetatable(cfg, library)
end

--// dropdown (toilet style: label above, box with "...", list drops below)
function library:dropdown(properties)
	local cfg = {
		name = properties.name or properties.Name,
		flag = properties.flag or properties.Flag or tostring(math.random(1000000, 9999999)),
		items = properties.items or properties.Options or { "option 1", "option 2", "option 3" },
		multi = properties.multi or properties.Multi or false,
		callback = properties.callback or properties.Callback or function() end,
		tooltip = properties.tooltip or properties.Tooltip,
		section = self,
		open = false,
		option_instances = {},
		selected = {},
	}

	local section = self
	cfg.default = properties.default or properties.Default or (cfg.multi and {} or cfg.items[1])

	-- outer + label
	local outer = library:create("Frame", {
		Parent = section.holder,
		Size = dim2(1, 0, 0, cfg.name and 32 or 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})

	if cfg.name then
		local label = library:create("TextLabel", {
			Parent = outer,
			Font = library.font,
			Text = cfg.name,
			TextSize = library.text_size,
			TextColor3 = library.theme.muted_text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = dim2(1, 0, 0, 13),
			BackgroundTransparency = 1,
		})

		register_theme(label, "muted_text", "TextColor3")
	end

	-- dropdown box
	local box = library:create("TextButton", {
		Parent = outer,
		Position = cfg.name and dim2(0, 0, 0, 16) or dim2(0, 0, 0, 2),
		Size = dim2(1, 0, 0, 18),
		BackgroundColor3 = library.theme.element,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ClipsDescendants = true,
	})

	library:corner(box, 4)
	register_theme(box, "element", "BackgroundColor3")

	local box_stroke = library:stroke(box, library.theme.outline, 1)
	register_theme(box_stroke, "outline", "Color")

	local box_label = library:create("TextLabel", {
		Parent = box,
		Font = library.font,
		Text = "",
		TextSize = library.text_size,
		TextColor3 = library.theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = dim2(0, 8, 0, 0),
		Size = dim2(1, -30, 1, 0),
		BackgroundTransparency = 1,
	})

	register_theme(box_label, "text", "TextColor3")

	local box_icon = library:create("TextLabel", {
		Parent = box,
		Font = library.font,
		Text = "...",
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = dim2(1, -22, 0, 0),
		Size = dim2(0, 14, 1, 0),
		BackgroundTransparency = 1,
	})

	register_theme(box_icon, "muted_text", "TextColor3")

	-- list window (floats under the box)
	local window = library:create("Frame", {
		Parent = library.gui,
		Visible = false,
		ZIndex = 120,
		Size = dim2(0, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = library.theme.element,
		BorderSizePixel = 0,
	})

	library:corner(window, 4)
	library:stroke(window, library.theme.outline, 1)
	register_theme(window, "element", "BackgroundColor3")

	local options = library:create("ScrollingFrame", {
		Parent = window,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 121,
		Size = dim2(1, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = dim2(0, 0, 0, 0),
		ScrollBarThickness = 1,
		ScrollBarImageColor3 = library.theme.inline,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})

	library:padding(options, 2, 2, 2, 2)
	library:list(options, 1)

	cfg.window = window
	cfg.trigger = box
	cfg.box = box
	cfg.box_label = box_label

	local function update_size()
		window.Size = dim2(0, box.AbsoluteSize.X, 0, 0)

		local height = math.min(#cfg.option_instances * 17 + 4, 17 * 8)
		options.Size = dim2(1, 0, 0, height)

		local position = box.AbsolutePosition
		local viewport = camera.ViewportSize

		local y = position.Y + box.AbsoluteSize.Y + 4
		if y + height > viewport.Y then
			y = position.Y - height - 4
		end

		window.Position = dim2(0, position.X, 0, y)
	end

	function cfg.set_visible(state)
		cfg.open = state

		if state then
			update_size()
		end

		window.Visible = state
		box_icon.Text = state and "x" or "..."
		box_stroke.Color = state and library.theme.accent or library.theme.outline

		if state then
			if library.current_element_open and library.current_element_open ~= cfg then
				library.current_element_open.set_visible(false)
				library.current_element_open.open = false
			end

			library.current_element_open = cfg
		elseif library.current_element_open == cfg then
			library.current_element_open = nil
		end
	end

	function cfg.set(value, silent)
		local selected = {}
		local is_table = type(value) == "table"

		for _, option in next, cfg.option_instances do
			if option.Text == value or (is_table and find(value, option.Text)) then
				option.TextColor3 = library.theme.accent
				insert(selected, option.Text)
			else
				option.TextColor3 = library.theme.muted_text
			end
		end

		cfg.selected = selected
		box_label.Text = is_table and ((#selected > 0) and table.concat(selected, ", ") or "--") or selected[1] or "--"

		library.flags[cfg.flag] = is_table and selected or selected[1]

		if not silent then
			cfg.callback(library.flags[cfg.flag])
		end
	end

	function cfg:refresh_options(items)
		cfg.items = items or cfg.items

		for _, option in next, cfg.option_instances do
			option:Destroy()
		end

		cfg.option_instances = {}

		for _, item in next, cfg.items do
			local option = library:create("TextButton", {
				Parent = options,
				Font = library.font,
				Text = item,
				TextSize = library.text_size,
				TextColor3 = library.theme.muted_text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = dim2(1, 0, 0, 16),
				BackgroundColor3 = library.theme.element,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				ZIndex = 122,
			})

			library:padding(option, 6, 6, 0, 0)
			insert(cfg.option_instances, option)

			option.MouseEnter:Connect(function()
				library:tween(option, 0.1, { TextColor3 = library.theme.text })
			end)

			option.MouseLeave:Connect(function()
				local is_selected = find(cfg.selected, item) ~= nil
				library:tween(option, 0.1, {
					TextColor3 = is_selected and library.theme.accent or library.theme.muted_text,
				})
			end)

			option.MouseButton1Down:Connect(function()
				if cfg.multi then
					local index = find(cfg.selected, item)

					if index then
						remove(cfg.selected, index)
					else
						insert(cfg.selected, item)
					end

					cfg.set(cfg.selected)
				else
					cfg.set_visible(false)
					cfg.open = false
					cfg.set(item)
				end
			end)
		end

		cfg.set(cfg.default, true)
	end

	box.MouseButton1Click:Connect(function()
		cfg.open = not cfg.open
		cfg.set_visible(cfg.open)
	end)

	if properties.tooltip or properties.Tooltip then
		library:hover_tooltip(box, properties.tooltip or properties.Tooltip)
	end

	cfg:refresh_options(cfg.items)

	library.config_flags[cfg.flag] = function(value)
		cfg.set(value, true)
		cfg.callback(value)
	end


	return setmetatable(cfg, library)
end

--// colorpicker (indigo swatches, compact hsv window)
function library:colorpicker(properties)
	local cfg = {
		name = properties.name or properties.Name,
		flag = properties.flag or properties.Flag or tostring(math.random(1000000, 9999999)),
		color = properties.color or properties.Color or library.theme.accent,
		transparency = properties.transparency or properties.Transparency or properties.alpha or 0,
		callback = properties.callback or properties.Callback or function() end,
		tooltip = properties.tooltip or properties.Tooltip,
		inline = properties.inline or false,
		open = false,
	}

	local section = properties.section or self
	local parent_holder = properties.parent_holder or section.holder

	local outer

	if cfg.inline then
		outer = parent_holder
	else
		outer = library:create("Frame", {
			Parent = section.holder,
			Size = dim2(1, 0, 0, cfg.name and 18 or 12),
			BackgroundTransparency = 1,
		})

		if cfg.name then
			local label = library:create("TextLabel", {
				Parent = outer,
				Font = library.font,
				Text = cfg.name,
				TextSize = library.text_size,
				TextColor3 = library.theme.muted_text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Size = dim2(1, -30, 1, 0),
				Position = dim2(0, 0, 0, 0),
				BackgroundTransparency = 1,
			})

			register_theme(label, "muted_text", "TextColor3")
		end
	end

	-- swatch (the little indigo square from the reference ui)
	local swatch_inline = library:create("TextButton", {
		Parent = outer,
		AnchorPoint = cfg.inline and vec2(0, 0.5) or vec2(1, 0.5),
		Position = cfg.inline and dim2(0, 0, 0.5, 0) or dim2(1, 0, 0.5, 0),
		Size = dim2(0, 20, 0, 10),
		BackgroundColor3 = cfg.color,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 3,
	})

	library:corner(swatch_inline, 3)

	local swatch_stroke = library:stroke(swatch_inline, library.theme.outline, 1)
	register_theme(swatch_stroke, "outline", "Color")

	local swatch = library:create("Frame", {
		Parent = swatch_inline,
		Position = dim2(0, 1, 0, 1),
		Size = dim2(1, -2, 1, -2),
		BackgroundColor3 = cfg.color,
		BorderSizePixel = 0,
		ZIndex = 4,
	})

	library:corner(swatch, 2)

	-- hsv window
	local window = library:create("Frame", {
		Parent = library.gui,
		Visible = false,
		ZIndex = 130,
		Size = dim2(0, 158, 0, 208),
		BackgroundColor3 = library.theme.element,
		BorderSizePixel = 0,
	})

	library:corner(window, 5)
	library:stroke(window, library.theme.outline, 1)
	register_theme(window, "element", "BackgroundColor3")

	local window_header = library:create("TextButton", {
		Parent = window,
		Size = dim2(1, 0, 0, 14),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 131,
	})

	local window_label = library:create("TextLabel", {
		Parent = window_header,
		Font = library.font,
		Text = cfg.name or "colorpicker",
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		BackgroundTransparency = 1,
		Position = dim2(0, 8, 0, 0),
		Size = dim2(1, -16, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 132,
	})

	register_theme(window_label, "muted_text", "TextColor3")

	-- saturation / value palette
	local palette = library:create("TextButton", {
		Parent = window,
		Position = dim2(0, 7, 0, 20),
		Size = dim2(1, -14, 0, 110),
		BackgroundColor3 = hsv(0, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 131,
	})

	library:corner(palette, 3)

	local white_overlay = library:create("Frame", {
		Parent = palette,
		Size = dim2(1, 0, 1, 0),
		BackgroundColor3 = rgb(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 132,
	})

	library:create("UIGradient", {
		Parent = white_overlay,
		ZIndex = 133,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})

	local black_overlay = library:create("Frame", {
		Parent = palette,
		Size = dim2(1, 0, 1, 0),
		BackgroundColor3 = rgb(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 133,
	})

	library:create("UIGradient", {
		Parent = black_overlay,
		Rotation = 270,
		ZIndex = 134,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})

	local palette_cursor = library:create("Frame", {
		Parent = palette,
		AnchorPoint = vec2(0.5, 0.5),
		Size = dim2(0, 6, 0, 6),
		BackgroundColor3 = rgb(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 135,
	})

	library:corner(palette_cursor, 3)
	library:stroke(palette_cursor, rgb(0, 0, 0), 1)

	-- hue bar
	local hue_bar = library:create("TextButton", {
		Parent = window,
		Position = dim2(0, 7, 0, 138),
		Size = dim2(1, -14, 0, 10),
		BackgroundColor3 = rgb(255, 255, 255),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 131,
	})

	library:corner(hue_bar, 3)

	library:create("UIGradient", {
		Parent = hue_bar,
		ZIndex = 132,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 0, 0)),
			ColorSequenceKeypoint.new(0.17, rgb(255, 255, 0)),
			ColorSequenceKeypoint.new(0.33, rgb(0, 255, 0)),
			ColorSequenceKeypoint.new(0.5, rgb(0, 255, 255)),
			ColorSequenceKeypoint.new(0.66, rgb(0, 0, 255)),
			ColorSequenceKeypoint.new(0.83, rgb(255, 0, 255)),
			ColorSequenceKeypoint.new(1, rgb(255, 0, 0)),
		}),
	})

	local hue_cursor = library:create("Frame", {
		Parent = hue_bar,
		AnchorPoint = vec2(0.5, 0.5),
		Position = dim2(0, 0, 0.5, 0),
		Size = dim2(0, 3, 0, 14),
		BackgroundColor3 = rgb(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 135,
	})

	library:corner(hue_cursor, 1)
	library:stroke(hue_cursor, rgb(0, 0, 0), 1)

	-- alpha bar
	local alpha_bar = library:create("TextButton", {
		Parent = window,
		Position = dim2(0, 7, 0, 156),
		Size = dim2(1, -14, 0, 10),
		BackgroundColor3 = cfg.color,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 131,
	})

	library:corner(alpha_bar, 3)

	local alpha_gradient = library:create("UIGradient", {
		Parent = alpha_bar,
		ZIndex = 132,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
	})

	local alpha_cursor = library:create("Frame", {
		Parent = alpha_bar,
		AnchorPoint = vec2(0.5, 0.5),
		Position = dim2(1, 0, 0.5, 0),
		Size = dim2(0, 3, 0, 14),
		BackgroundColor3 = rgb(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 135,
	})

	library:corner(alpha_cursor, 1)
	library:stroke(alpha_cursor, rgb(0, 0, 0), 1)

	-- hex preview
	local hex_label = library:create("TextLabel", {
		Parent = window,
		Font = library.font,
		Text = "#56 56 ff",
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		BackgroundTransparency = 1,
		Position = dim2(0, 8, 1, -16),
		Size = dim2(1, -16, 0, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 131,
	})

	register_theme(hex_label, "muted_text", "TextColor3")


	cfg.window = window
	cfg.trigger = swatch_inline
	cfg.section = section
	cfg.parent_holder = properties.parent_holder

	-- chain a keybind after this colorpicker (e.g. toggle:colorpicker():keybind())
	function cfg.keybind(properties_override)
		local chained_properties = properties_override or {}

		chained_properties.chained = true
		chained_properties.section = section
		chained_properties.parent_holder = cfg.parent_holder

		return library:keybind(chained_properties)
	end

	-- hsv state from the default color
	local h, s, v = cfg.color:ToHSV()
	cfg.hue, cfg.saturation, cfg.value = h, s, v

	local function update()
		cfg.color = hsv(cfg.hue, cfg.saturation, cfg.value)

		swatch.BackgroundColor3 = cfg.color
		swatch.BackgroundTransparency = cfg.transparency
		palette.BackgroundColor3 = hsv(cfg.hue, 1, 1)
		alpha_bar.BackgroundColor3 = cfg.color

		palette_cursor.Position = dim2(cfg.saturation, 0, 1 - cfg.value, 0)
		hue_cursor.Position = dim2(cfg.hue, 0, 0.5, 0)
		alpha_cursor.Position = dim2(1 - cfg.transparency, 0, 0.5, 0)

		alpha_gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, cfg.color),
			ColorSequenceKeypoint.new(1, cfg.color),
		})

		local red, green, blue = floor(cfg.color.R * 255), floor(cfg.color.G * 255), floor(cfg.color.B * 255)
		hex_label.Text = string.format("#%02x%02x%02x %.2f", red, green, blue, 1 - cfg.transparency)

		library.flags[cfg.flag] = {
			Color = cfg.color,
			Hex = cfg.color:ToHex(),
			Transparency = cfg.transparency,
		}
	end

	function cfg.set(color, transparency, silent)
		if type(color) == "table" and color.Color then
			cfg.transparency = color.Transparency or 0
			color = color.Color
		end

		if type(color) == "string" then
			color = hex(color)
		end

		cfg.hue, cfg.saturation, cfg.value = color:ToHSV()
		cfg.transparency = clamp(tonumber(cfg.transparency) or 0, 0, 1)

		update()

		if not silent then
			cfg.callback(cfg.color, cfg.transparency)
		end
	end

	function cfg.set_visible(state)
		cfg.open = state

		if state then
			local position = swatch_inline.AbsolutePosition
			local viewport = camera.ViewportSize
			local x = clamp(position.X + swatch_inline.AbsoluteSize.X + 6, 4, viewport.X - window.Size.X.Offset - 6)
			local y = clamp(position.Y + 16, 0, viewport.Y - window.Size.Y.Offset - 6)

			window.Position = dim2(0, x, 0, y)

			if library.current_element_open and library.current_element_open ~= cfg then
				library.current_element_open.set_visible(false)
				library.current_element_open.open = false
			end

			library.current_element_open = cfg
		elseif library.current_element_open == cfg then
			library.current_element_open = nil
		end

		window.Visible = state
	end

	swatch_inline.MouseButton1Click:Connect(function()
		cfg.set_visible(not cfg.open)
	end)

	-- copy / paste (right click copies, middle click pastes)
	swatch_inline.MouseButton2Click:Connect(function()
		library.copied_color = cfg.color
		library:notification({ text = "copied color", time = 2 })
	end)

	swatch_inline.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton3 and library.copied_color then
			cfg.set(library.copied_color)
		end
	end)

	-- dragging helpers
	local drag_target = nil

	local function palette_input()
		local position = palette.AbsolutePosition
		local size = palette.AbsoluteSize
		local mouse_position = get_mouse()

		cfg.saturation = clamp((mouse_position.X - position.X) / size.X, 0, 1)
		cfg.value = clamp(1 - (mouse_position.Y - position.Y) / size.Y, 0, 1)

		update()
		cfg.callback(cfg.color, cfg.transparency)
	end

	local function hue_input()
		local position = hue_bar.AbsolutePosition
		local mouse_position = get_mouse()

		cfg.hue = clamp((mouse_position.X - position.X) / hue_bar.AbsoluteSize.X, 0, 1)

		update()
		cfg.callback(cfg.color, cfg.transparency)
	end

	local function alpha_input()
		local position = alpha_bar.AbsolutePosition
		local mouse_position = get_mouse()

		cfg.transparency = clamp(1 - (mouse_position.X - position.X) / alpha_bar.AbsoluteSize.X, 0, 1)

		update()
		cfg.callback(cfg.color, cfg.transparency)
	end

	palette.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			drag_target = "palette"
			palette_input()
		end
	end)

	hue_bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			drag_target = "hue"
			hue_input()
		end
	end)

	alpha_bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			drag_target = "alpha"
			alpha_input()
		end
	end)

	library:connection(uis.InputChanged, function(input)
		if drag_target and input.UserInputType == Enum.UserInputType.MouseMovement then
			if drag_target == "palette" then
				palette_input()
			elseif drag_target == "hue" then
				hue_input()
			elseif drag_target == "alpha" then
				alpha_input()
			end
		end
	end)

	library:connection(uis.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			drag_target = nil
		end
	end)

	-- draggable window
	local dragging, drag_start, start_position

	window_header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			drag_start = input.Position
			start_position = window.Position
		end
	end)

	library:connection(uis.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	library:connection(uis.InputChanged, function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - drag_start
			window.Position = dim2(0, start_position.X.Offset + delta.X, 0, start_position.Y.Offset + delta.Y)
		end
	end)

	if properties.tooltip or properties.Tooltip then
		library:hover_tooltip(swatch_inline, properties.tooltip or properties.Tooltip)
	end

	cfg.set(cfg.color, cfg.transparency, true)
	cfg.callback(cfg.color, cfg.transparency)

	library.config_flags[cfg.flag] = function(value, transparency)
		if type(value) == "table" and value.Color then
			cfg.transparency = value.Transparency or transparency or 0
			value = value.Color
		elseif transparency ~= nil then
			cfg.transparency = transparency
		end

		cfg.set(value, cfg.transparency, true)
		cfg.callback(cfg.color, cfg.transparency)
	end


	return setmetatable(cfg, library)
end

--// button (toilet style: gray rounded, full / half / third widths in rows)
function library:button(properties)
	local cfg = {
		name = properties.name or properties.text or properties.Name or "Button",
		callback = properties.callback or properties.Callback or function() end,
		tooltip = properties.tooltip or properties.Tooltip,
		section = self,
	}

	local section = self
	local fraction = properties.size or properties.Size or 1

	local holder

	if fraction < 1 then
		local row = section.current_row

		if not row or row.remaining < fraction then
			row = library:create("Frame", {
				Parent = section.holder,
				Size = dim2(1, 0, 0, 18),
				BackgroundTransparency = 1,
			})

			library:list(row, 3, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
			section.current_row = { frame = row, remaining = 1 }
		end

		holder = row.frame
		section.current_row.remaining = section.current_row.remaining - fraction
	else
		section.current_row = nil

		holder = library:create("Frame", {
			Parent = section.holder,
			Size = dim2(1, 0, 0, 18),
			BackgroundTransparency = 1,
		})
	end

	local button = library:create("TextButton", {
		Parent = holder,
		Font = library.font,
		Text = cfg.name,
		TextSize = library.text_size,
		TextColor3 = library.theme.text,
		Size = dim2(fraction, fraction < 1 and -3 or 0, 1, 0),
		BackgroundColor3 = library.theme.element,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		LayoutOrder = section.__button_order or 0,
	})

	section.__button_order = (section.__button_order or 0) + 1

	library:corner(button, 4)
	register_theme(button, "element", "BackgroundColor3")

	local button_stroke = library:stroke(button, library.theme.outline, 1)
	register_theme(button_stroke, "outline", "Color")

	button.MouseEnter:Connect(function()
		library:tween(button, 0.12, { BackgroundColor3 = library.theme.element_hover })
	end)

	button.MouseLeave:Connect(function()
		library:tween(button, 0.12, { BackgroundColor3 = library.theme.element })
		button_stroke.Color = library.theme.outline
	end)

	button.MouseButton1Down:Connect(function()
		button_stroke.Color = library.theme.accent
	end)

	button.MouseButton1Click:Connect(function()
		cfg.callback()
	end)

	if properties.tooltip or properties.Tooltip then
		library:hover_tooltip(button, properties.tooltip or properties.Tooltip)
	end

	return setmetatable(cfg, library)
end

--// textbox
function library:textbox(properties)
	local cfg = {
		name = properties.name or properties.Name,
		flag = properties.flag or properties.Flag or tostring(math.random(1000000, 9999999)),
		placeholder = properties.placeholder or properties.Placeholder or properties.placeholdertext or "type here...",
		default = properties.default or properties.Default,
		clear_on_focus = properties.clear_on_focus or false,
		callback = properties.callback or properties.Callback or function() end,
		tooltip = properties.tooltip or properties.Tooltip,
		section = self,
	}

	local section = self

	local outer = library:create("Frame", {
		Parent = section.holder,
		Size = dim2(1, 0, 0, cfg.name and 32 or 20),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	})

	if cfg.name then
		local label = library:create("TextLabel", {
			Parent = outer,
			Font = library.font,
			Text = cfg.name,
			TextSize = library.text_size,
			TextColor3 = library.theme.muted_text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = dim2(1, 0, 0, 13),
			BackgroundTransparency = 1,
		})

		register_theme(label, "muted_text", "TextColor3")
	end

	local box = library:create("TextBox", {
		Parent = outer,
		Font = library.font,
		Text = "",
		TextSize = library.text_size,
		TextColor3 = library.theme.text,
		PlaceholderText = cfg.placeholder,
		PlaceholderColor3 = library.theme.muted_text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = cfg.clear_on_focus,
		Position = cfg.name and dim2(0, 0, 0, 16) or dim2(0, 0, 0, 2),
		Size = dim2(1, 0, 0, 18),
		BackgroundColor3 = library.theme.element,
		BorderSizePixel = 0,
	})

	library:corner(box, 4)
	register_theme(box, "element", "BackgroundColor3")

	local box_stroke = library:stroke(box, library.theme.outline, 1)
	register_theme(box_stroke, "outline", "Color")

	library:padding(box, 8, 8, 0, 0)

	box.Focused:Connect(function()
		library:tween(box_stroke, 0.12, { Color = library.theme.accent })
	end)

	box.FocusLost:Connect(function(enter_pressed)
		library:tween(box_stroke, 0.12, { Color = library.theme.outline })

		library.flags[cfg.flag] = box.Text
		cfg.callback(box.Text, enter_pressed)
	end)

	function cfg.set(text, silent)
		box.Text = text
		library.flags[cfg.flag] = text

		if not silent then
			cfg.callback(text)
		end
	end

	if cfg.default then
		cfg.set(cfg.default, true)
	end

	if properties.tooltip or properties.Tooltip then
		library:hover_tooltip(box, properties.tooltip or properties.Tooltip)
	end

	library.config_flags[cfg.flag] = function(value)
		cfg.set(value, true)
		cfg.callback(value)
	end

	return setmetatable(cfg, library)
end

--// label
function library:label(properties)
	local cfg = {
		name = properties.name or properties.text or properties.Name or "label",
		section = self,
	}

	local section = self

	local label = library:create("TextLabel", {
		Parent = section.holder,
		Font = library.font,
		Text = cfg.name,
		TextSize = library.text_size,
		TextColor3 = properties.color or properties.Color or library.theme.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = dim2(1, 0, 0, 13),
		BackgroundTransparency = 1,
	})

	register_theme(label, "text", "TextColor3")

	cfg.label = label

	function cfg.set(text)
		label.Text = text
	end

	return setmetatable(cfg, library)
end

--// divider
function library:divider()
	local section = self

	local line = library:create("Frame", {
		Parent = section.holder,
		Size = dim2(1, 0, 0, 1),
		BackgroundColor3 = library.theme.inline,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
	})

	register_theme(line, "inline", "BackgroundColor3")
	return line
end

--// listbox (rune style selection box: click an option to select it)
function library:listbox(properties)
	local cfg = {
		flag = properties.flag or properties.Flag or tostring(math.random(1000000, 9999999)),
		items = properties.items or properties.Options or {},
		callback = properties.callback or properties.Callback or function() end,
		tooltip = properties.tooltip or properties.Tooltip,
		section = self,
		option_instances = {},
	}

	local section = self
	cfg.default = properties.default or properties.Default

	local box = library:create("Frame", {
		Parent = section.holder,
		Size = dim2(1, 0, 0, #cfg.items * 15 + 8),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = library.theme.outline,
		BorderSizePixel = 0,
	})

	library:corner(box, 4)
	register_theme(box, "outline", "BackgroundColor3")

	local box_stroke = library:stroke(box, library.theme.inline, 1)
	register_theme(box_stroke, "inline", "Color")

	library:padding(box, 2, 2, 2, 2)
	library:list(box, 2)

	cfg.box = box

	function cfg.set(value, silent)
		for _, option in next, cfg.option_instances do
			if option.Text == value then
				library:tween(option, 0.12, { BackgroundColor3 = library.theme.element })
				library:tween(option, 0.12, { TextColor3 = library.theme.accent })
			else
				library:tween(option, 0.12, { BackgroundColor3 = library.theme.outline })
				library:tween(option, 0.12, { TextColor3 = library.theme.muted_text })
			end
		end

		library.flags[cfg.flag] = value

		if not silent then
			cfg.callback(value)
		end
	end

	for _, item in next, cfg.items do
		local option = library:create("TextButton", {
			Parent = box,
			Font = library.font,
			Text = item,
			TextSize = library.text_size,
			TextColor3 = library.theme.muted_text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = dim2(1, 0, 0, 15),
			BackgroundColor3 = library.theme.outline,
			BorderSizePixel = 0,
			AutoButtonColor = false,
		})

		library:padding(option, 6, 6, 0, 0)
		insert(cfg.option_instances, option)

		option.MouseEnter:Connect(function()
			if library.flags[cfg.flag] ~= item then
				library:tween(option, 0.1, { TextColor3 = library.theme.text })
			end
		end)

		option.MouseLeave:Connect(function()
			if library.flags[cfg.flag] ~= item then
				library:tween(option, 0.1, { TextColor3 = library.theme.muted_text })
			end
		end)

		option.MouseButton1Click:Connect(function()
			cfg.set(item)
		end)
	end

	if properties.tooltip or properties.Tooltip then
		library:hover_tooltip(box, properties.tooltip or properties.Tooltip)
	end

	if cfg.default then
		cfg.set(cfg.default, true)
	end

	library.config_flags[cfg.flag] = function(value)
		cfg.set(value, true)
		cfg.callback(value)
	end

	return setmetatable(cfg, library)
end

--// keybind (click to bind, right click to cycle mode: toggle / hold / always)
function library:keybind(properties)
	local cfg = {
		name = properties.name or properties.Name,
		flag = properties.flag or properties.Flag or tostring(math.random(1000000, 9999999)),
		mode = properties.mode or properties.Mode or "toggle",
		default = properties.default or properties.Default,
		callback = properties.callback or properties.Callback or function() end,
		changed = properties.changed or properties.Changed or function() end,
		tooltip = properties.tooltip or properties.Tooltip,
		section = properties.section or self,
		chained = properties.chained or false,
		key = nil,
		active = false,
		listening = false,
	}

	local section = cfg.section
	local parent_holder = properties.parent_holder or section.holder

	local outer

	if cfg.chained then
		outer = parent_holder
	else
		outer = library:create("Frame", {
			Parent = parent_holder,
			Size = dim2(1, 0, 0, 16),
			BackgroundTransparency = 1,
		})

		if cfg.name then
			local label = library:create("TextLabel", {
				Parent = outer,
				Font = library.font,
				Text = cfg.name,
				TextSize = library.text_size,
				TextColor3 = library.theme.muted_text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Position = dim2(0, 18, 0, 0),
				Size = dim2(1, -18, 1, 0),
				BackgroundTransparency = 1,
			})

			register_theme(label, "muted_text", "TextColor3")
		end
	end

	local display = library:create("TextButton", {
		Parent = outer,
		Font = library.font,
		Text = "[ ]",
		TextSize = library.text_size,
		TextColor3 = library.theme.muted_text,
		AnchorPoint = cfg.chained and vec2(0, 0.5) or vec2(1, 0.5),
		Position = cfg.chained and dim2(0, 0, 0.5, 0) or dim2(1, 0, 0.5, 0),
		Size = dim2(0, 30, 0, 12),
		BackgroundTransparency = 1,
		TextXAlignment = cfg.chained and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right,
	})

	register_theme(display, "muted_text", "TextColor3")

	cfg.display = display

	local modes = { "toggle", "hold", "always" }

	function cfg.set(key, silent)
		cfg.key = key

		display.Text = key and (keys[key] or (key.Name and key.Name or tostring(key))) or "[ ]"
		library.flags[cfg.flag] = { key = key, mode = cfg.mode, active = cfg.active }

		if not silent then
			cfg.changed(key)
		end
	end

	function cfg.set_active(state)
		cfg.active = state

		if library.flags[cfg.flag] then
			library.flags[cfg.flag].active = state
		end

		display.TextColor3 = state and library.theme.accent or library.theme.muted_text
		cfg.callback(state)
	end

	function cfg.set_mode(mode)
		cfg.mode = mode

		if library.flags[cfg.flag] then
			library.flags[cfg.flag].mode = mode
		end

		cfg.set_active(false)
	end

	display.MouseButton1Click:Connect(function()
		if library.keybind_listening and library.keybind_listening ~= cfg then
			return
		end

		cfg.listening = true
		library.keybind_listening = cfg
		display.Text = "[...]"
		library:remove_tooltip()
	end)

	display.MouseButton2Click:Connect(function()
		local index = find(modes, cfg.mode) or 1
		cfg.set_mode(modes[(index % #modes) + 1])
		library:notification({ text = "keybind mode: " .. cfg.mode, time = 2 })
	end)

	if properties.tooltip or properties.Tooltip then
		library:hover_tooltip(display, properties.tooltip or properties.Tooltip)
	end

	library:connection(uis.InputBegan, function(input, game_processed)
		if library.keybind_listening == cfg then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				if input.KeyCode == Enum.KeyCode.Escape then
					cfg.set(nil, true)
				else
					cfg.set(input.KeyCode)
				end

				cfg.listening = false
				library.keybind_listening = nil
				return
			elseif find({ Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3 }, input.UserInputType) then
				cfg.set(input.UserInputType)
				cfg.listening = false
				library.keybind_listening = nil
				return
			end

			return
		end

		if game_processed or not cfg.key then
			return
		end

		if input.KeyCode == cfg.key or input.UserInputType == cfg.key then
			if cfg.mode == "toggle" then
				cfg.set_active(not cfg.active)
			elseif cfg.mode == "hold" then
				cfg.set_active(true)
			elseif cfg.mode == "always" then
				if not cfg.active then
					cfg.set_active(true)
				end
			end
		end
	end)

	library:connection(uis.InputEnded, function(input)
		if not cfg.key then
			return
		end

		if cfg.mode == "hold" and (input.KeyCode == cfg.key or input.UserInputType == cfg.key) then
			cfg.set_active(false)
		end
	end)

	if cfg.default then
		cfg.set(cfg.default, true)
	end

	library.config_flags[cfg.flag] = function(value)
		if type(value) == "table" then
			cfg.set_mode(value.mode or cfg.mode)
			cfg.set(value.key, true)
		else
			cfg.set(value, true)
		end
	end

	-- chain a colorpicker after this keybind (e.g. toggle:keybind():colorpicker())
	function cfg.colorpicker(properties_override)
		local chained_properties = properties_override or {}

		chained_properties.inline = cfg.chained
		chained_properties.section = section
		chained_properties.parent_holder = parent_holder

		return library:colorpicker(chained_properties)
	end

	return setmetatable(cfg, library)
end

--// config system
local function ensure_directories()
	pcall(function()
		if makefolder then
			makefolder(library.directory)

			for _, folder in next, library.folders do
				makefolder(library.directory .. folder)
			end
		end
	end)
end

ensure_directories()

function library:get_config()
	local config = {}

	for flag, value in next, library.flags do
		if type(value) == "table" and value.key then
			config[flag] = { key = tostring(value.key), mode = value.mode, active = value.active }
		elseif type(value) == "table" and value.Color then
			config[flag] = { Color = value.Color:ToHex(), Transparency = value.Transparency }
		elseif type(value) == "table" and value[1] == nil then
			-- empty multi dropdown
			config[flag] = {}
		else
			config[flag] = value
		end
	end

	return http_service:JSONEncode(config)
end

function library:load_config(config_json)
	local ok, config = pcall(function()
		return http_service:JSONDecode(config_json)
	end)

	if not ok or type(config) ~= "table" then
		library:notification({ text = "failed to read config", time = 3 })
		return
	end

	for flag, value in next, config do
		local setter = library.config_flags[flag]

		if setter then
			if type(value) == "table" and value.Color then
				local success, color = pcall(function()
					return hex(value.Color)
				end)

				if success and color then
					setter(color, value.Transparency or 0)
				end
			elseif type(value) == "table" and value.key then
				local success, enum = pcall(function()
					return library:convert_enum(value.key)
				end)

				if success and enum then
					setter({ key = enum, mode = value.mode or "toggle", active = false })
				end
			else
				setter(value)
			end
		end
	end

	library:notification({ text = "config loaded", time = 3 })
end

function library:convert_enum(enum_string)
	local parts = string.split(enum_string, ".")

	if parts[1] == "Enum" and parts[2] == "UserInputType" then
		return Enum.UserInputType[parts[3]]
	elseif parts[1] == "Enum" and parts[2] == "KeyCode" then
		return Enum.KeyCode[parts[3]]
	end

	return nil
end

function library:save_config(name)
	local path = library.directory .. "/configs/" .. tostring(name) .. ".json"

	pcall(function()
		writefile(path, library:get_config())
	end)

	library:notification({ text = "saved config: " .. tostring(name), time = 3 })
end

function library:load_config_file(name)
	local path = library.directory .. "/configs/" .. tostring(name) .. ".json"

	pcall(function()
		library:load_config(readfile(path))
	end)
end

function library:get_configs()
	local configs = {}

	pcall(function()
		for _, file in next, listfiles(library.directory .. "/configs") do
			local name = string.gsub(file, library.directory .. "/configs/", "")
			name = string.gsub(name, "%.json$", "")
			insert(configs, name)
		end
	end)

	return configs
end

return library















