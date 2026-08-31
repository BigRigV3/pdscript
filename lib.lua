--[[═════════════════════════════════════════════════════════════════════════
    TypeShit ESP v1.2 • typeshit.cc private
    ──────────────────────────────────────────────────────────────────────────
    A self-contained, high-performance ESP library built on the executor
    Drawing API (Line / Square / Text / Circle), with a graceful Instance-based
    fallback renderer for environments without Drawing support.

    FEATURES
      • Pixel-perfect rendering — every coordinate rounded to whole pixels
      • Box ESP — "square" | "chamfer" (rounded corners) | "corner" brackets
      • Health bar — smooth animated vertical or horizontal gradient bar
      • Chams — occluded Highlights, see players through walls
      • Auto-scale boxes — sized from the real character bounds (R6/R15)
      • Tool text — equipped weapon name under the box
      • Name + Distance — outlined text, username style ("cassenderekmason")
      • Skeleton ESP — R6 + R15 stick figures drawn with Line objects
      • Ping status dot — live latency dot beside the name
      • Tracers (optional) — bottom / center / top screen origin
      • Team check + team colors, wall check (dim or hide occluded players)
      • Object pooling + change-detection caching (near-zero GC churn)
      • 500-stud default range, BindToRenderStep at camera priority

    USAGE
      1. Copy this whole file into your executor and press Execute.
         The ESP starts immediately and tracks every player automatically.
      2. Runtime control through the EspLib global:
             EspLib.Toggle()              EspLib.Toggle(true / false)
             EspLib.Unload()              -- removes everything, full cleanup
             EspLib.Refresh()             -- re-applies the config to live ESP
             EspLib.CreateESP(player)     EspLib.RemoveESP(player)
             EspLib.UpdateESP(dt)         -- manual single-frame update
             EspLib.Config.Name.Size = 16 -- every option is live-editable
      3. Re-executing the script cleanly replaces the previous instance.

    COMPATIBILITY
      • Synapse X / Z, Script-Ware, Krnl, Fluxus, Oxygen U, Wave, Delta, ...
      • If your executor treats Drawing.Transparency like Roblox instances
        (0 = opaque instead of 1 = opaque) and everything looks invisible,
        set  EspLib.Config.Compat.InvertTransparency = true  and Refresh().
════════════════════════════════════════════════════════════════════════════]]

-- Guard against double execution: cleanly remove a previous instance first.
local GLOBAL = _G
pcall(function()
    local g = getgenv and getgenv()
    if type(g) == "table" then GLOBAL = g end
end)

do
    local previous = GLOBAL.EspLib
    if type(previous) == "table" and type(previous.Unload) == "function" then
        pcall(previous.Unload)
    end
end

--══════════════════════════════════════════════════════════════════════════
-- 1. CONFIGURATION — everything you may want to tweak lives here
--══════════════════════════════════════════════════════════════════════════

local Config = {
    Enabled     = true,   -- master switch (also EspLib.Toggle())
    MaxDistance = 500,    -- studs; players further away are never drawn
    ToggleKey   = nil,    -- e.g. Enum.KeyCode.RightControl for a hotkey

    TeamCheck    = false, -- true: teammates are never drawn
    TeamColors   = true,  -- true: teammates use Colors.Friendly
    UseTeamColor = false, -- true: use each player's Roblox TeamColor instead
    WallCheck    = true,  -- true: raycast toward players; occluded ones are
    VisibleOnly  = false, --   hidden when true, dimmed when false (Colors.Dim)

    Font = 3,             -- 3 = Monospace: Monocraft-style pixel font
                          -- (0 = UI   1 = System   2 = Plex)

    Box = {
        Enabled        = true,
        Style          = "square",  -- "square" | "chamfer" (rounded) | "corner"
        Corner         = 6,         -- corner cut size in pixels for "chamfer"
        Outline        = true,      -- black contrast outline behind the border
        OutlineOpacity = 0.85,
        Opacity        = 1,         -- border opacity 0..1
        Fill           = true,      -- semi-transparent fill inside the box
        FillOpacity    = 0.5,       -- fill opacity 0..1 (0.5 = 50% see-through)
        AutoScale      = true,      -- size boxes from the real character bounds
        MaxSizeStuds   = 25,        -- AutoScale safety clamp (giant/ragdolled rigs)
        WidthRatio     = "auto",    -- legacy width (used when AutoScale = false)
        HeightScale    = 3,         -- legacy height (used when AutoScale = false)
    },

    HealthBar = {
        Enabled     = true,
        Side        = "Left",  -- "Left" (vertical) | "Bottom" (horizontal)
        Padding     = 3,       -- gap between the bar and the box in pixels
        Thickness   = 4,       -- total bar thickness in pixels (incl. 1px frame)
        Smooth      = true,    -- animate health changes with a lerp
        SmoothSpeed = 12,      -- lerp speed (higher = snappier)
        ShowNumber     = true,      -- floating HP number
        NumberPosition = "Left",    -- "Left" (beside the bar) | "TopLeft" | "Right"
        NumberSize     = 11,
    },

    Name = {
        Enabled        = true,
        Size           = 14,
        UseDisplayName = false, -- false = raw username, like "cassenderekmason"
    },

    Distance = {
        Enabled  = true,
        Size     = 12,
        Position = "TopRight", -- "TopRight" (image style) | "Top" (under name)
    },

    Skeleton = {
        Enabled   = true,
        Thickness = 1,
        Opacity   = 0.9,
    },

    PingDot = {
        Enabled = false,  -- latency dot beside the name (needs Name.Enabled)
        Radius  = 2,
        GoodMs  = 80,     -- green at or below
        OkayMs  = 160,    -- yellow at or below, red above
    },

    Tracers = {
        Enabled   = false,
        Origin    = "Bottom", -- "Bottom" | "Center" | "Top"
        Thickness = 1,
        Opacity   = 0.9,
    },

    Chams = {
        Enabled      = true,
        Color        = Color3.fromRGB(255, 70, 70), -- fill seen through walls
        Transparency = 0,    -- chams fill transparency (0..1)
    },

    ToolText = {
        Enabled = true,
        Size    = 12,        -- equipped weapon name under the box
    },

    Colors = {
        Enemy    = Color3.fromRGB(255, 90, 90),    -- salmon red (image style)
        Friendly = Color3.fromRGB(122, 255, 82),   -- lime green
        Name     = Color3.fromRGB(255, 255, 255),  -- soft white
        Distance = Color3.fromRGB(190, 190, 190),  -- light gray
        Outline  = Color3.fromRGB(0, 0, 0),        -- text / bar backdrop
        Fill     = nil,                            -- nil = tint with player color
        Skeleton = nil,                            -- nil = match the border color
        Dim      = 0.45,                           -- occluded color multiplier
        PingGood = Color3.fromRGB(85, 255, 127),
        PingOkay = Color3.fromRGB(255, 196, 0),
        PingBad  = Color3.fromRGB(255, 72, 72),
    },

    Compat = {
        -- Drawing.Transparency conventions differ between executors: most use
        -- 1 = opaque. If visuals look inverted on yours, flip this to true.
        InvertTransparency = false,
    },
}

--══════════════════════════════════════════════════════════════════════════
-- 2. SERVICES, SHIMS & STATE
--══════════════════════════════════════════════════════════════════════════

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    -- extremely-early execution safety net
    pcall(function()
        Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    end)
    LocalPlayer = Players.LocalPlayer
end

local Camera = Workspace.CurrentCamera

-- RaycastFilterType was renamed Blacklist -> Exclude across client versions.
local RAY_FILTER
if pcall(function() return Enum.RaycastFilterType.Exclude end) then
    RAY_FILTER = Enum.RaycastFilterType.Exclude
else
    RAY_FILTER = Enum.RaycastFilterType.Blacklist
end

-- Internally the library works with OPACITY (1 = solid, 0 = invisible) and
-- converts to whichever Transparency convention the executor expects.
local function alpha(opacity)
    if Config.Compat.InvertTransparency then return 1 - opacity end
    return opacity
end

-- Tracked state
local EspLib          -- forward declaration of the public API table
local objects     = {} -- player -> ESP bundle
local pool        = {} -- released bundles, ready for reuse
local connections = {} -- global event connections
local running     = true


--══════════════════════════════════════════════════════════════════════════
-- 3. DRAWING ADAPTER
--   Uses the native executor Drawing API when present; otherwise builds a
--   faithful substitute from Instances (Frame / TextLabel / UICorner /
--   UIStroke) parented to gethui() / CoreGui / PlayerGui.
--══════════════════════════════════════════════════════════════════════════

local NewDrawing            -- function(class) -> drawing object
local USING_NATIVE = false  -- true when the real Drawing API is available
local FallbackGui           -- ScreenGui used by the fallback renderer

do
    local dtype = type(Drawing)
    if dtype == "table" and type(Drawing.new) == "function" then
        NewDrawing = Drawing.new
        USING_NATIVE = true
    elseif dtype == "function" then
        NewDrawing = Drawing
        USING_NATIVE = true
    else
        --------------------------------------------------------------------
        -- Instance-based fallback renderer
        --------------------------------------------------------------------
        local FONT_MAP = {
            [0] = Enum.Font.SourceSans, -- "UI"
            [1] = Enum.Font.Arial,      -- "System"
            [2] = Enum.Font.Gotham,     -- "Plex"
            [3] = Enum.Font.Code,       -- "Monospace"
        }
        local state = setmetatable({}, { __mode = "k" }) -- instance -> side data

        FallbackGui = Instance.new("ScreenGui")
        FallbackGui.Name = "EspLib_Fallback"
        FallbackGui.ResetOnSpawn = false
        FallbackGui.IgnoreGuiInset = true -- viewport coords == screen coords
        FallbackGui.DisplayOrder = 9999
        FallbackGui.ZIndexBehavior = Enum.ZIndexBehavior.Global

        do -- parent as high as the environment allows
            local ok = pcall(function()
                FallbackGui.Parent = (type(gethui) == "function") and gethui()
                    or game:GetService("CoreGui")
            end)
            if not ok or not FallbackGui.Parent then
                pcall(function()
                    FallbackGui.Parent = LocalPlayer:FindFirstChild("PlayerGui")
                end)
            end
        end

        -- A Line becomes a rotated frame between From and To.
        local function lineGeometry(inst)
            local s = state[inst]
            local f, t = s.from, s.to
            local dx, dy = t.X - f.X, t.Y - f.Y
            local len = math.sqrt(dx * dx + dy * dy)
            inst.AnchorPoint = Vector2.new(0.5, 0.5)
            inst.Position = UDim2.fromOffset((f.X + t.X) * 0.5, (f.Y + t.Y) * 0.5)
            inst.Size = UDim2.fromOffset(math.max(len, 0.01), s.thickness or 1)
            inst.Rotation = math.deg(math.atan2(dy, dx))
        end

        -- Squares render as fill (Filled=true) or as a UIStroke ring.
        local function refreshSquare(inst)
            local s = state[inst]
            if s.filled then
                inst.BackgroundTransparency = 1 - s.transparency
                inst.BackgroundColor3 = s.color
                if s.stroke then s.stroke.Enabled = false end
            else
                inst.BackgroundTransparency = 1
                if s.stroke then
                    s.stroke.Enabled = true
                    s.stroke.Color = s.color
                    s.stroke.Transparency = 1 - s.transparency
                    s.stroke.Thickness = s.thickness or 1
                end
            end
        end

        -- Circles are square frames with a UICorner; Position is the CENTER,
        -- matching the native Drawing.Circle convention.
        local function refreshCircle(inst)
            local s = state[inst]
            local r = s.radius or 4
            inst.AnchorPoint = Vector2.new(0.5, 0.5)
            inst.Position = UDim2.fromOffset(s.x or 0, s.y or 0)
            inst.Size = UDim2.fromOffset(r * 2, r * 2)
            inst.BackgroundColor3 = s.color
            if s.filled then
                inst.BackgroundTransparency = 1 - s.transparency
                if s.stroke then s.stroke.Enabled = false end
            else
                inst.BackgroundTransparency = 1
                if s.stroke then
                    s.stroke.Enabled = true
                    s.stroke.Color = s.color
                    s.stroke.Transparency = 1 - s.transparency
                    s.stroke.Thickness = s.thickness or 1
                end
            end
        end

        local function applyText(inst, k, v)
            if k == "Position" then
                inst.Position = UDim2.fromOffset(v.X, v.Y)
            elseif k == "Text" then
                inst.Text = v
            elseif k == "TextSize" then
                inst.TextSize = v
                inst.Size = UDim2.fromOffset(800, v + 6)
            elseif k == "Color" then
                inst.TextColor3 = v
            elseif k == "Transparency" then
                inst.TextTransparency = 1 - v
            elseif k == "Center" then
                inst.AnchorPoint = v and Vector2.new(0.5, 0) or Vector2.new(0, 0)
                inst.TextXAlignment = v and Enum.TextXAlignment.Center
                    or Enum.TextXAlignment.Left
            elseif k == "Outline" then
                inst.TextStrokeTransparency = v and 0 or 1
            elseif k == "OutlineColor" then
                inst.TextStrokeColor3 = v
            elseif k == "Font" then
                inst.Font = FONT_MAP[v] or FONT_MAP[0]
            end
        end


        local APPLIERS = {
            Square = function(inst, k, v)
                local s = state[inst]
                if k == "Filled" then s.filled = v
                elseif k == "Thickness" then s.thickness = v
                elseif k == "Position" then inst.Position = UDim2.fromOffset(v.X, v.Y)
                elseif k == "Size" then inst.Size = UDim2.fromOffset(v.X, v.Y)
                elseif k == "Color" then s.color = v
                elseif k == "Transparency" then s.transparency = v
                end
                refreshSquare(inst)
            end,
            Line = function(inst, k, v)
                local s = state[inst]
                if k == "From" then s.from = v
                elseif k == "To" then s.to = v
                elseif k == "Thickness" then s.thickness = v
                elseif k == "Color" then inst.BackgroundColor3 = v
                elseif k == "Transparency" then inst.BackgroundTransparency = 1 - v
                end
                if k == "From" or k == "To" or k == "Thickness" then
                    lineGeometry(inst)
                end
            end,
            Text = applyText,
            Circle = function(inst, k, v)
                local s = state[inst]
                if k == "Position" then s.x, s.y = v.X, v.Y
                elseif k == "Radius" then s.radius = v
                elseif k == "Filled" then s.filled = v
                elseif k == "Thickness" then s.thickness = v
                elseif k == "Color" then s.color = v
                elseif k == "Transparency" then s.transparency = v
                end
                refreshCircle(inst)
            end,
        }

        NewDrawing = function(class)
            local instClass = (class == "Text") and "TextLabel" or "Frame"
            local inst = Instance.new(instClass)
            inst.BorderSizePixel = 0
            inst.BackgroundColor3 = Color3.new(1, 1, 1)
            inst.BackgroundTransparency = 1
            inst.Visible = false
            inst.Parent = FallbackGui

            local s = {
                transparency = 1, color = Color3.new(1, 1, 1),
                from = Vector2.new(0, 0), to = Vector2.new(0, 0),
                radius = 4, thickness = 1, filled = false, x = 0, y = 0,
            }
            if instClass == "Frame" then
                local stroke = Instance.new("UIStroke")
                stroke.Enabled = false
                stroke.Parent = inst
                s.stroke = stroke
                if class == "Circle" then
                    local corner = Instance.new("UICorner")
                    corner.CornerRadius = UDim.new(1, 0)
                    corner.Parent = inst
                end
            end
            state[inst] = s

            -- The proxy mimics a Drawing object; property writes are applied
            -- to the backing instance immediately.
            local props = {}
            return setmetatable({}, {
                __index = function(_, k)
                    if k == "Remove" or k == "Destroy" then
                        return function()
                            props.Visible = false
                            state[inst] = nil
                            pcall(function() inst:Destroy() end)
                        end
                    elseif k == "TextBounds" then
                        return inst.TextBounds
                    end
                    return props[k]
                end,
                __newindex = function(_, k, v)
                    props[k] = v
                    if k == "Visible" then
                        inst.Visible = v and true or false
                    elseif k == "ZIndex" then
                        inst.ZIndex = v
                    else
                        local apply = APPLIERS[class]
                        if apply then apply(inst, k, v) end
                    end
                end,
            })
        end
    end
end


--══════════════════════════════════════════════════════════════════════════
-- 4. UTILITIES
--══════════════════════════════════════════════════════════════════════════

-- Lua 5.1-safe helpers (no dependency on Luau-only globals like math.round).
local function round(n) return math.floor(n + 0.5) end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Red -> green health gradient through HSV hue space (0 = red, 0.33 = green).
local function healthColor(ratio)
    return Color3.fromHSV(clamp(ratio, 0, 1) * 0.33, 0.85, 1)
end

-- Darken a color for occluded ("through wall") players.
local function dimColor(c, k)
    return Color3.new(c.R * k, c.G * k, c.B * k)
end

-- Change-detection helpers. Property writes on Drawing objects cross the
-- Lua/C boundary every call, so the library only writes a property when its
-- value actually changed.  This is the single biggest performance win.
local function setVisible(o, want)
    if o.Visible ~= want then o.Visible = want end
end

local COLOR_CACHE = setmetatable({}, { __mode = "k" })
local function setColor(o, col)
    if COLOR_CACHE[o] ~= col then
        COLOR_CACHE[o] = col
        o.Color = col
    end
end

local function setLine(o, cache, i, x1, y1, x2, y2)
    local c = cache[i]
    if not c then c = { -1, -1, -1, -1 } cache[i] = c end
    if c[1] ~= x1 or c[2] ~= y1 or c[3] ~= x2 or c[4] ~= y2 then
        c[1], c[2], c[3], c[4] = x1, y1, x2, y2
        o.From = Vector2.new(x1, y1)
        o.To   = Vector2.new(x2, y2)
    end
end

local function setRect(o, cache, i, x, y, w, h)
    local c = cache[i]
    if not c then c = { -1, -1, -1, -1 } cache[i] = c end
    if c[1] ~= x or c[2] ~= y or c[3] ~= w or c[4] ~= h then
        c[1], c[2], c[3], c[4] = x, y, w, h
        o.Position = Vector2.new(x, y)
        o.Size     = Vector2.new(w, h)
    end
end

local function setText(o, cache, text, x, y)
    if cache[1] ~= x or cache[2] ~= y or cache[3] ~= text then
        cache[1], cache[2], cache[3] = x, y, text
        o.Position = Vector2.new(x, y)
        o.Text     = text
    end
end

local function setCircle(o, cache, x, y, r)
    if cache[1] ~= x or cache[2] ~= y or cache[3] ~= r then
        cache[1], cache[2], cache[3] = x, y, r
        o.Position = Vector2.new(x, y)
        o.Radius   = r
    end
end

-- Hides every drawing of a bundle; cheap no-op while already hidden.
local function hidePlayer(data)
    if not data.hidden then
        data.hidden = true
        local all = data.all
        for i = 1, #all do
            local o = all[i]
            if o.Visible then o.Visible = false end
        end
    end
end

-- ── executor quirk shims ─────────────────────────────────────────────────
-- Historical Drawing implementations disagree on the text font-size property
-- name: some expose "TextSize", Synapse-style APIs expose "Size" (and error
-- on "TextSize").  Probe which one the executor accepts, then stick to it.
local TEXT_SIZE_PROP = "TextSize"

local function setTextSize(d, size)
    if TEXT_SIZE_PROP == "Size" then
        d.Size = size
        return
    end
    local ok = pcall(function() d.TextSize = size end)
    if not ok then
        TEXT_SIZE_PROP = "Size" -- executor uses the Synapse convention
        pcall(function() d.Size = size end)
    end
end

-- Rare executors lack Font / OutlineColor on Text drawings; degrade
-- gracefully instead of erroring (both are purely cosmetic).
local FONT_OK = true
local function setTextFont(d, font)
    if FONT_OK then
        FONT_OK = pcall(function() d.Font = font end)
    end
end

local OUTLINE_COLOR_OK = true
local function setTextOutline(d, color)
    if OUTLINE_COLOR_OK then
        OUTLINE_COLOR_OK = pcall(function() d.OutlineColor = color end)
    end
end


--══════════════════════════════════════════════════════════════════════════
-- 5. GEOMETRY & CHARACTER BINDING
--══════════════════════════════════════════════════════════════════════════

local BONE_COUNT = 14

-- Rig bone maps: chains of { parentPartName, childPartName }.
local R15_BONES = {
    { "Head", "UpperTorso" },
    { "UpperTorso", "LowerTorso" },
    { "LowerTorso", "LeftUpperLeg" },  { "LeftUpperLeg", "LeftLowerLeg" },
    { "LeftLowerLeg", "LeftFoot" },
    { "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" },
    { "RightLowerLeg", "RightFoot" },
    { "UpperTorso", "LeftUpperArm" },  { "LeftUpperArm", "LeftLowerArm" },
    { "LeftLowerArm", "LeftHand" },
    { "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" },
    { "RightLowerArm", "RightHand" },
}
local R6_BONES = {
    { "Head", "Torso" },
    { "Torso", "Left Arm" },  { "Torso", "Right Arm" },
    { "Torso", "Left Leg" },  { "Torso", "Right Leg" },
}

-- Resolves the bone parts of a character once, when it is assigned.
local function buildBones(char)
    local map = R6_BONES
    if char:FindFirstChild("UpperTorso") then map = R15_BONES end
    local bones = {}
    for i = 1, #map do
        local pair = map[i]
        bones[i] = { char:FindFirstChild(pair[1]), char:FindFirstChild(pair[2]) }
    end
    return bones
end

-- Box width relative to box height. R15 rigs are slimmer than R6.
local R15_RATIO, R6_RATIO = 0.60, 0.72

local function getBoxWidthRatio(data)
    local r = Config.Box.WidthRatio
    if r == "auto" then
        local hum = data.hum
        if hum and hum.RigType == Enum.HumanoidRigType.R15 then
            return R15_RATIO
        end
        return R6_RATIO
    end
    return r
end

-- Reusable scratch table for border segments (zero allocations per frame).
local SEG = {}
for i = 1, 8 do SEG[i] = {} end

-- Builds the 4 or 8 border segments for the configured box style and returns
-- how many segments were written into SEG.
local function buildSegments(bx, by, bw, bh)
    local style = Config.Box.Style
    if style == "corner" then
        local lx = clamp(round(bw * 0.25), 6, math.floor(bw * 0.5) - 1)
        local ly = clamp(round(bh * 0.25), 6, math.floor(bh * 0.5) - 1)
        local s = SEG[1]; s[1], s[2], s[3], s[4] = bx,           by,      bx + lx,      by
        s = SEG[2];       s[1], s[2], s[3], s[4] = bx,           by,      bx,           by + ly
        s = SEG[3];       s[1], s[2], s[3], s[4] = bx + bw - lx, by,      bx + bw,      by
        s = SEG[4];       s[1], s[2], s[3], s[4] = bx + bw,      by,      bx + bw,      by + ly
        s = SEG[5];       s[1], s[2], s[3], s[4] = bx,           by + bh, bx + lx,      by + bh
        s = SEG[6];       s[1], s[2], s[3], s[4] = bx,           by + bh - ly, bx,      by + bh
        s = SEG[7];       s[1], s[2], s[3], s[4] = bx + bw - lx, by + bh, bx + bw,      by + bh
        s = SEG[8];       s[1], s[2], s[3], s[4] = bx + bw,      by + bh - ly, bx + bw, by + bh
        return 8
    end
    local r = 0
    if style == "chamfer" then
        r = clamp(Config.Box.Corner or 6, 2, math.floor(math.min(bw, bh) * 0.5) - 1)
        if bw < r * 2 + 4 or bh < r * 2 + 4 then r = 0 end -- tiny boxes stay square
    end
    local s = SEG[1]; s[1], s[2], s[3], s[4] = bx + r,      by,      bx + bw - r, by
    s = SEG[2];       s[1], s[2], s[3], s[4] = bx + r,      by + bh, bx + bw - r, by + bh
    s = SEG[3];       s[1], s[2], s[3], s[4] = bx,          by + r,  bx,          by + bh - r
    s = SEG[4];       s[1], s[2], s[3], s[4] = bx + bw,     by + r,  bx + bw,     by + bh - r
    if r > 0 then
        s = SEG[5]; s[1], s[2], s[3], s[4] = bx,          by + r,  bx + r,      by
        s = SEG[6]; s[1], s[2], s[3], s[4] = bx + bw - r, by,      bx + bw,     by + r
        s = SEG[7]; s[1], s[2], s[3], s[4] = bx,          by + bh - r, bx + r,  by + bh
        s = SEG[8]; s[1], s[2], s[3], s[4] = bx + bw - r, by + bh, bx + bw,     by + bh - r
        return 8
    end
    return 4
end

-- Snug bounding box (center + size) from the character's DIRECT BaseParts.
-- R6/R15 body parts are direct children, so equipped tools (Tool > Handle)
-- and accessory handles are naturally excluded. Uses part AABBs, so heavily
-- rotated limbs can widen the box slightly.
local function computeBounds(char)
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local found = false
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") then
            found = true
            local pos, half = p.Position, p.Size * 0.5
            minX = math.min(minX, pos.X - half.X)
            maxX = math.max(maxX, pos.X + half.X)
            minY = math.min(minY, pos.Y - half.Y)
            maxY = math.max(maxY, pos.Y + half.Y)
            minZ = math.min(minZ, pos.Z - half.Z)
            maxZ = math.max(maxZ, pos.Z + half.Z)
        end
    end
    if not found then return nil, nil end
    local center = Vector3.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
    local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
    return center, size
end

-- Removes a player's occluded-chams Highlight.
local function destroyChams(data)
    if data.chams then
        pcall(function() data.chams:Destroy() end)
        data.chams = nil
    end
end

-- Caches character references, skeleton bones and raycast parameters.
local function bindCharacter(data, char)
    data.char  = char
    data.root  = char:FindFirstChild("HumanoidRootPart")
    data.hum   = char:FindFirstChildOfClass("Humanoid")
    data.bones = buildBones(char)
    data.shownHP = 1
    if data.hum and data.hum.MaxHealth > 0 then
        data.shownHP = clamp(data.hum.Health / data.hum.MaxHealth, 0, 1)
    end

    -- Auto-scale bounds: the box follows the real R6/R15/scaled avatar size.
    data.boundCenter, data.boundSize = nil, nil
    if Config.Box.AutoScale then
        local c, s = computeBounds(char)
        local maxS = Config.Box.MaxSizeStuds or 25
        if c and s and s.Y >= 0.5 and s.Y <= maxS
           and math.max(s.X, s.Z) <= maxS then
            data.boundCenter, data.boundSize = c, s
        end
    end

    -- Occluded chams: DepthMode=Occluded renders the fill ONLY where the
    -- character is behind geometry, so you see the color through walls and
    -- the normal character up close. Highlight is local-only and dies with
    -- the character; note that many simultaneous Highlights cost GPU time.
    destroyChams(data)
    if Config.Chams.Enabled then
        local ok = pcall(function()
            local h = Instance.new("Highlight")
            h.Name = "EspLib_Chams"
            h.FillColor = Config.Chams.Color
            h.FillTransparency = clamp(Config.Chams.Transparency or 0, 0, 1)
            h.OutlineColor = Config.Chams.Color
            h.OutlineTransparency = 1
            h.DepthMode = Enum.HighlightDepthMode.Occluded
            h.Parent = char
            data.chams = h
        end)
        if not ok then data.chams = nil end
    end

    local params = data.rayParams
    local exclude = {}
    if LocalPlayer.Character then exclude[#exclude + 1] = LocalPlayer.Character end
    exclude[#exclude + 1] = char
    params.FilterDescendantsInstances = exclude
    params.FilterType = RAY_FILTER
    params.IgnoreWater = true
end

-- True when world geometry stands between the camera and the target root.
local function isOccluded(origin, target, dist, params)
    local hit = Workspace:Raycast(origin, target - origin, params)
    if hit and hit.Position then
        if (hit.Position - origin).Magnitude < dist - 1 then return true end
    end
    return false
end


--══════════════════════════════════════════════════════════════════════════
-- 6. OBJECT POOL & BUNDLE FACTORY
--   A "bundle" owns every Drawing object one player can ever need.  Bundles
--   are recycled through a pool, so players joining/leaving never create or
--   destroy Drawing objects in steady state.
--══════════════════════════════════════════════════════════════════════════

local function makeBundle()
    local d, all = {}, {}
    local function reg(o) all[#all + 1] = o return o end

    -- Box border (8 lines covers every style) + black contrast outline
    d.box, d.boxO = {}, {}
    for i = 1, 8 do
        local l = NewDrawing("Line")
        l.Thickness, l.Transparency, l.ZIndex, l.Visible = 1, alpha(Config.Box.Opacity or 1), 2, false
        reg(l); d.box[i] = l
        local o = NewDrawing("Line")
        o.Thickness, o.Transparency, o.ZIndex, o.Visible = 3, alpha(Config.Box.OutlineOpacity or 0.85), 1, false
        reg(o); d.boxO[i] = o
    end

    -- Fill (brightest glow core) + health bar
    d.fill = reg(NewDrawing("Square"))
    d.fill.Filled, d.fill.Thickness, d.fill.ZIndex, d.fill.Visible = true, 1, 2, false

    d.hpBG = reg(NewDrawing("Square"))
    d.hpBG.Filled, d.hpBG.Transparency, d.hpBG.ZIndex, d.hpBG.Visible = true, alpha(0.7), 2, false
    d.hpFG = reg(NewDrawing("Square"))
    d.hpFG.Filled, d.hpFG.Transparency, d.hpFG.ZIndex, d.hpFG.Visible = true, alpha(1), 3, false

    -- Texts (name / distance / hp number / tool)
    d.name = reg(NewDrawing("Text"))
    d.name.Center, d.name.Outline, d.name.ZIndex, d.name.Visible = true, true, 5, false
    d.dist = reg(NewDrawing("Text"))
    d.dist.Center, d.dist.Outline, d.dist.ZIndex, d.dist.Visible = true, true, 5, false
    d.hpNum = reg(NewDrawing("Text"))
    d.hpNum.Center, d.hpNum.Outline, d.hpNum.ZIndex, d.hpNum.Visible = false, true, 5, false
    d.tool = reg(NewDrawing("Text"))
    d.tool.Center, d.tool.Outline, d.tool.ZIndex, d.tool.Visible = true, true, 5, false

    -- Ping status dot
    d.dot = reg(NewDrawing("Circle"))
    d.dot.Filled, d.dot.NumSides, d.dot.Thickness, d.dot.ZIndex, d.dot.Visible = true, 16, 1, 5, false

    -- Skeleton (R6 uses 5 of the 14 lines)
    d.bones = {}
    for i = 1, BONE_COUNT do
        local l = NewDrawing("Line")
        l.Thickness, l.Transparency, l.ZIndex, l.Visible = Config.Skeleton.Thickness or 1, alpha(Config.Skeleton.Opacity or 0.9), 2, false
        reg(l); d.bones[i] = l
    end

    -- Tracer
    d.tracer = reg(NewDrawing("Line"))
    d.tracer.Thickness, d.tracer.Transparency, d.tracer.ZIndex, d.tracer.Visible = Config.Tracers.Thickness or 1, alpha(Config.Tracers.Opacity or 0.9), 1, false

    return {
        d = d, all = all,
        last = {
            box = {}, boxO = {}, bones = {}, fill = {}, hpBG = {}, hpFG = {},
            name = {}, dist = {}, hpNum = {}, dot = {}, tracer = {},
            tool = {},
        },
        hidden = true, plr = nil,
        char = nil, root = nil, hum = nil, bones = nil,
        rayParams = RaycastParams.new(),
        shownHP = 1, pingT = 0, pingMs = nil, hasBounds = nil,
        conns = nil,
    }
end

-- Applies config-dependent static properties (on acquire + EspLib.Refresh).
local function applyStatic(data)
    local d = data.d
    if not d then return end
    for i = 1, 8 do
        d.box[i].Thickness = 1
        d.box[i].Transparency = alpha(Config.Box.Opacity or 1)
        d.boxO[i].Thickness = 3
        d.boxO[i].Transparency = alpha(Config.Box.OutlineOpacity or 0.85)
        d.boxO[i].Color = Config.Colors.Outline
    end
    d.fill.Transparency = alpha(Config.Box.FillOpacity or 0.5)
    d.hpBG.Transparency = alpha(0.7)
    d.hpFG.Transparency = alpha(1)
    setTextSize(d.name, Config.Name.Size or 14)
    setTextFont(d.name, Config.Font)
    setTextOutline(d.name, Config.Colors.Outline)
    setTextSize(d.dist, Config.Distance.Size or 12)
    setTextFont(d.dist, Config.Font)
    setTextOutline(d.dist, Config.Colors.Outline)
    setTextSize(d.hpNum, Config.HealthBar.NumberSize or 11)
    setTextFont(d.hpNum, Config.Font)
    setTextOutline(d.hpNum, Config.Colors.Outline)
    d.hpNum.Center = (Config.HealthBar.NumberPosition == "Left") and true or false
    d.dist.Center = (Config.Distance.Position ~= "TopRight") and true or false
    setTextSize(d.tool, Config.ToolText.Size or 12)
    setTextFont(d.tool, Config.Font)
    setTextOutline(d.tool, Config.Colors.Outline)
    for i = 1, BONE_COUNT do
        d.bones[i].Thickness = Config.Skeleton.Thickness or 1
        d.bones[i].Transparency = alpha(Config.Skeleton.Opacity or 0.9)
    end
    d.tracer.Thickness = Config.Tracers.Thickness or 1
    d.tracer.Transparency = alpha(Config.Tracers.Opacity or 0.9)
end

local function removeDrawing(o)
    if not pcall(o.Remove, o) then pcall(o.Destroy, o) end
end

local function destroyBundle(data)
    local all = data.all
    if all then
        for i = 1, #all do removeDrawing(all[i]) end
    end
    data.d, data.all, data.last = nil, nil, nil
end

local MAX_POOL = 8

local function poolAcquire()
    local data = table.remove(pool) or makeBundle()
    applyStatic(data)
    return data
end

local function poolRelease(data)
    hidePlayer(data)
    data.plr, data.char, data.root, data.hum = nil, nil, nil, nil
    data.bones, data.conns = nil, nil
    if #pool < MAX_POOL then
        pool[#pool + 1] = data
    else
        destroyBundle(data)
    end
end


--══════════════════════════════════════════════════════════════════════════
-- 7. LIFECYCLE — CreateESP / RemoveESP
--══════════════════════════════════════════════════════════════════════════

local function CreateESP(plr)
    if not plr or plr == LocalPlayer or objects[plr] then return end
    local data = poolAcquire()
    data.plr = plr
    data.hasBounds = nil -- re-probe TextBounds support for this bundle
    data.pingT, data.pingMs = 0, nil
    objects[plr] = data

    local conns = {}
    conns[#conns + 1] = plr.CharacterAdded:Connect(function(char)
        if objects[plr] == data then bindCharacter(data, char) end
    end)
    conns[#conns + 1] = plr.CharacterRemoving:Connect(function()
        data.char, data.root, data.hum, data.bones = nil, nil, nil, nil
        destroyChams(data)
        hidePlayer(data)
    end)
    data.conns = conns

    if plr.Character then bindCharacter(data, plr.Character) end
end

local function RemoveESP(plr, destroy)
    local data = plr and objects[plr]
    if not data then return end
    objects[plr] = nil
    if data.conns then
        for i = 1, #data.conns do
            pcall(data.conns[i].Disconnect, data.conns[i])
        end
        data.conns = nil
    end
    destroyChams(data)
    if destroy then
        destroyBundle(data)
    else
        poolRelease(data)
    end
end

--══════════════════════════════════════════════════════════════════════════
-- 8. PER-FRAME RENDER — UpdateESP
--══════════════════════════════════════════════════════════════════════════

local function updatePlayer(data, dt, camPos, viewport, myTeam)
    local plr = data.plr
    if not plr or not data.d then return hidePlayer(data) end
    local d = data.d

    -- ── resolve character references ─────────────────────────────────────
    local char = plr.Character
    if not char then return hidePlayer(data) end
    if data.char ~= char then bindCharacter(data, char) end

    local root, hum = data.root, data.hum
    if not root or not hum then
        -- Character may still be streaming in; (re)acquire references.
        root = char:FindFirstChild("HumanoidRootPart")
        hum  = char:FindFirstChildOfClass("Humanoid")
        data.root, data.hum = root, hum
        if not root or not hum then return hidePlayer(data) end
    end
    if hum.Health <= 0 then return hidePlayer(data) end

    -- ── culling: distance / team / screen / walls ────────────────────────
    local rootPos = root.Position
    local dist = (rootPos - camPos).Magnitude
    if dist > Config.MaxDistance then return hidePlayer(data) end

    local sameTeam = (myTeam ~= nil and plr.Team == myTeam)
    if Config.TeamCheck and sameTeam then return hidePlayer(data) end

    -- ── bounding box (auto-scaled to the character's real bounds) ────────
    local anchorPos, hs = rootPos, Config.Box.HeightScale or 3
    if data.boundCenter and data.boundSize then
        anchorPos = data.boundCenter
        hs = data.boundSize.Y * 0.5
    end
    local center, onScreen = Camera:WorldToViewportPoint(anchorPos)
    if not onScreen or center.Z <= 0 or center.X ~= center.X then
        return hidePlayer(data) -- off screen / behind camera / NaN
    end

    local occluded = false
    if Config.WallCheck then
        occluded = isOccluded(camPos, rootPos, dist, data.rayParams)
        if occluded and Config.VisibleOnly then return hidePlayer(data) end
    end

    -- ── palette ──────────────────────────────────────────────────────────
    local col = Config.Colors.Enemy
    if Config.UseTeamColor and plr.TeamColor then
        col = plr.TeamColor.Color
    elseif sameTeam then
        col = Config.Colors.Friendly
    end
    if occluded then col = dimColor(col, Config.Colors.Dim or 0.45) end
    data.hidden = false

    -- ── bounding box (3 projections, pixel-aligned) ──────────────────────
    local topP = Camera:WorldToViewportPoint(anchorPos + Vector3.new(0, hs, 0))
    local botP = Camera:WorldToViewportPoint(anchorPos - Vector3.new(0, hs, 0))
    local boxH = botP.Y - topP.Y
    if boxH ~= boxH or boxH < 2 then return hidePlayer(data) end -- NaN / degenerate

    local boxW
    if data.boundSize then
        -- auto-scale: width from the character's real horizontal extent
        boxW = math.max(data.boundSize.X, data.boundSize.Z) * (boxH / data.boundSize.Y)
    else
        boxW = boxH * getBoxWidthRatio(data)
    end
    local bx = round(center.X - boxW * 0.5)
    local by = round(topP.Y)
    local bw = round(boxW)
    local bh = round(boxH)

    local count = Config.Box.Enabled and buildSegments(bx, by, bw, bh) or 0
    for i = 1, 8 do
        local line, out = d.box[i], d.boxO[i]
        if i <= count then
            local s = SEG[i]
            setLine(line, data.last.box, i, s[1], s[2], s[3], s[4])
            setColor(line, col)
            setVisible(line, true)
            if Config.Box.Outline then
                setLine(out, data.last.boxO, i, s[1], s[2], s[3], s[4])
                setVisible(out, true)
            else
                setVisible(out, false)
            end
        else
            setVisible(line, false)
            setVisible(out, false)
        end
    end

    -- ── box fill ─────────────────────────────────────────────────────────
    if Config.Box.Enabled and Config.Box.Fill then
        setRect(d.fill, data.last.fill, 1,
            bx + 2, by + 2, math.max(bw - 4, 1), math.max(bh - 4, 1))
        setColor(d.fill, Config.Colors.Fill or col)
        setVisible(d.fill, true)
    else
        setVisible(d.fill, false)
    end


    -- ── health bar (animated lerp, red -> green gradient) ────────────────
    local hb = Config.HealthBar
    if hb.Enabled then
        local max = hum.MaxHealth
        local target = clamp(hum.Health / (max > 0 and max or 100), 0, 1)
        if hb.Smooth then
            local a = clamp((dt or 0.016) * (hb.SmoothSpeed or 12), 0, 1)
            data.shownHP = data.shownHP + (target - data.shownHP) * a
            if math.abs(target - data.shownHP) < 0.002 then
                data.shownHP = target
            end
        else
            data.shownHP = target
        end
        local shown = data.shownHP
        local th = math.max(hb.Thickness or 4, 3)
        local pad = hb.Padding or 3
        local hc = healthColor(shown)

        if hb.Side == "Bottom" then
            setRect(d.hpBG, data.last.hpBG, 1, bx - 1, by + bh + pad, bw + 2, th)
            setRect(d.hpFG, data.last.hpFG, 1, bx, by + bh + pad + 1,
                math.max(round((bw - 2) * shown), 1), th - 2)
        else
            setRect(d.hpBG, data.last.hpBG, 1, bx - pad - th, by - 1, th, bh + 2)
            local fh = math.max(round(bh * shown), 1)
            setRect(d.hpFG, data.last.hpFG, 1, bx - pad - th + 1, by + bh - fh, th - 2, fh)
        end
        setColor(d.hpBG, Config.Colors.Outline)
        setColor(d.hpFG, hc)
        setVisible(d.hpBG, true)
        setVisible(d.hpFG, true)

        if hb.ShowNumber then
            local nx, ny
            local npos = hb.NumberPosition or "Left"
            if npos == "TopLeft" then
                nx, ny = bx, by - (hb.NumberSize or 11) - 3
            elseif npos == "Left" then
                nx, ny = bx - pad - th - 12, by + 2
            elseif hb.Side == "Bottom" then
                nx, ny = bx + bw + 4, by + bh + pad
            else
                nx = bx + bw + 4
                ny = by + bh - round(bh * shown) - 6
                if ny < by then ny = by end
            end
            setText(d.hpNum, data.last.hpNum, tostring(math.ceil(hum.Health)), nx, ny)
            setColor(d.hpNum, hc)
            setVisible(d.hpNum, true)
        else
            setVisible(d.hpNum, false)
        end
    else
        setVisible(d.hpBG, false)
        setVisible(d.hpFG, false)
        setVisible(d.hpNum, false)
    end

    -- ── name + distance (outlined, centered, pixel aligned) ──────────────
    local nameSize = Config.Name.Size or 14
    local nameY = by - nameSize - 5
    if Config.Name.Enabled then
        local label = Config.Name.UseDisplayName and plr.DisplayName or plr.Name
        setText(d.name, data.last.name, label, round(center.X), nameY)
        setColor(d.name, Config.Colors.Name)
        setVisible(d.name, true)
    else
        setVisible(d.name, false)
    end

    if Config.Distance.Enabled then
        local dx, dy
        if Config.Distance.Position == "TopRight" then
            dx, dy = bx + bw + 4, by
        else
            dx = round(center.X)
            dy = Config.Name.Enabled and (nameY + nameSize + 1)
                or (by - (Config.Distance.Size or 12) - 5)
        end
        setText(d.dist, data.last.dist,
            string.format("%dm", math.floor(dist + 0.5)), dx, dy)
        setColor(d.dist, Config.Colors.Distance)
        setVisible(d.dist, true)
    else
        setVisible(d.dist, false)
    end

    -- ── tool text (equipped weapon name under the box) ───────────────────
    local tt = Config.ToolText
    if tt.Enabled then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then
            local ty = by + bh + 5
            if Config.HealthBar.Enabled and Config.HealthBar.Side == "Bottom" then
                ty = ty + (Config.HealthBar.Padding or 3) + (Config.HealthBar.Thickness or 4)
            end
            setText(d.tool, data.last.tool, tool.Name, round(center.X), ty)
            setColor(d.tool, Config.Colors.Distance)
            setVisible(d.tool, true)
        else
            setVisible(d.tool, false)
        end
    else
        setVisible(d.tool, false)
    end


    -- ── ping status dot (uses TextBounds when the executor exposes it) ───
    local pd = Config.PingDot
    if pd.Enabled and Config.Name.Enabled then
        if data.hasBounds == nil then
            local ok, b = pcall(function() return d.name.TextBounds end)
            data.hasBounds = (ok and b ~= nil) and true or false
        end
        local placed = false
        if data.hasBounds then
            local b = d.name.TextBounds
            if b and b.X and b.X > 0 then
                data.pingT = data.pingT + (dt or 0)
                if data.pingMs == nil or data.pingT >= 1 then
                    data.pingT = 0
                    local okP, s = pcall(plr.GetNetworkPing, plr)
                    data.pingMs = (okP and s and s > 0)
                        and math.floor(s * 2000 + 0.5) or 0 -- approx RTT ms
                end
                local ms = data.pingMs or 0
                local pc
                if ms <= (pd.GoodMs or 80) then pc = Config.Colors.PingGood
                elseif ms <= (pd.OkayMs or 160) then pc = Config.Colors.PingOkay
                else pc = Config.Colors.PingBad end
                setCircle(d.dot, data.last.dot,
                    round(center.X - b.X * 0.5) - 8,
                    round(nameY + nameSize * 0.5), pd.Radius or 2)
                setColor(d.dot, pc)
                setVisible(d.dot, true)
                placed = true
            end
        end
        if not placed then setVisible(d.dot, false) end
    else
        setVisible(d.dot, false)
    end

    -- ── skeleton (hide individual bones that fail to project) ────────────
    if Config.Skeleton.Enabled and data.bones then
        local scol = Config.Colors.Skeleton or col
        for i = 1, BONE_COUNT do
            local line = d.bones[i]
            local bone = data.bones[i]
            local drawn = false
            if bone then
                local p1, p2 = bone[1], bone[2]
                if p1 and p2 and p1.Parent and p2.Parent then
                    local a, aOn = Camera:WorldToViewportPoint(p1.Position)
                    local b2, bOn = Camera:WorldToViewportPoint(p2.Position)
                    if aOn and bOn and a.Z > 0 and b2.Z > 0 then
                        setLine(line, data.last.bones, i,
                            round(a.X), round(a.Y), round(b2.X), round(b2.Y))
                        setColor(line, scol)
                        setVisible(line, true)
                        drawn = true
                    end
                end
            end
            if not drawn then setVisible(line, false) end
        end
    else
        for i = 1, BONE_COUNT do setVisible(d.bones[i], false) end
    end

    -- ── tracer ───────────────────────────────────────────────────────────
    local tr = Config.Tracers
    if tr.Enabled then
        local ox = round(viewport.X * 0.5)
        local oy = viewport.Y
        if tr.Origin == "Center" then oy = round(viewport.Y * 0.5)
        elseif tr.Origin == "Top" then oy = 0 end
        setLine(d.tracer, data.last.tracer, 1, ox, oy, round(center.X), by + bh)
        setColor(d.tracer, col)
        setVisible(d.tracer, true)
    else
        setVisible(d.tracer, false)
    end
end

local function UpdateESP(dt)
    Camera = Workspace.CurrentCamera or Camera
    if not Camera then return end
    local camPos = Camera.CFrame.Position
    local viewport = Camera.ViewportSize
    local myTeam = LocalPlayer and LocalPlayer.Team or nil
    for _, data in pairs(objects) do
        updatePlayer(data, dt, camPos, viewport, myTeam)
    end
end


--══════════════════════════════════════════════════════════════════════════
-- 9. FRAME LOOP, EVENTS & PUBLIC API
--══════════════════════════════════════════════════════════════════════════

local RENDER_NAME = "EspLib_RenderStep"

local function onStep(dt)
    if not running then return end
    if not Config.Enabled then
        for _, data in pairs(objects) do hidePlayer(data) end
        return
    end
    UpdateESP(dt)
end

-- Prefer BindToRenderStep (runs right after the camera updates -> zero lag);
-- fall back to a plain RenderStepped connection on older executors.
do
    local bound = pcall(function()
        RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onStep)
    end)
    if not bound then
        connections[#connections + 1] = RunService.RenderStepped:Connect(onStep)
    end
end

-- Full cleanup: disconnects events, destroys every pooled Drawing object
-- and removes the EspLib global. Safe to call twice.
local function Unload()
    if not running then return end
    running = false
    pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
    for i = 1, #connections do
        pcall(connections[i].Disconnect, connections[i])
    end
    connections = {}
    for plr in pairs(objects) do
        RemoveESP(plr, true)
    end
    while #pool > 0 do
        destroyBundle(table.remove(pool))
    end
    if FallbackGui then
        pcall(function() FallbackGui:Destroy() end)
        FallbackGui = nil
    end
    GLOBAL.EspLib = nil
    GLOBAL.TypeShit = nil
end

EspLib = {
    _VERSION = "1.2.0",
    Config   = Config,

    Toggle = function(state)
        if state == nil then
            Config.Enabled = not Config.Enabled
        else
            Config.Enabled = state and true or false
        end
        return Config.Enabled
    end,
    IsEnabled = function() return Config.Enabled end,
    CreateESP = CreateESP,
    RemoveESP = function(plr) RemoveESP(plr, false) end,
    UpdateESP = function(dt)
        if running then UpdateESP(dt or (1 / 60)) end
    end,
    Refresh = function()
        for _, data in pairs(objects) do applyStatic(data) end
    end,
    GetBundle = function(plr) return objects[plr] end,
    Rebind = function()
        -- re-runs character binding: recomputes auto-scale bounds and
        -- recreates chams with the current config
        for _, data in pairs(objects) do
            if data.char then bindCharacter(data, data.char) end
        end
    end,
    Unload    = Unload,

    -- internals, exposed for debugging and testing
    _internal = { objects = objects, pool = pool, Config = Config },
}
GLOBAL.EspLib = EspLib
GLOBAL.TypeShit = EspLib -- branded alias (typeshit.cc private)

-- Keep raycast exclusions valid when the local character respawns.
pcall(function()
    connections[#connections + 1] = LocalPlayer.CharacterAdded:Connect(function()
        for _, data in pairs(objects) do
            if data.char then bindCharacter(data, data.char) end
        end
    end)
end)

-- Follow camera swaps and roster changes.
connections[#connections + 1] = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
end)
connections[#connections + 1] = Players.PlayerAdded:Connect(CreateESP)
connections[#connections + 1] = Players.PlayerRemoving:Connect(function(plr)
    RemoveESP(plr, false)
end)

-- Optional hotkey (set Config.ToggleKey, e.g. Enum.KeyCode.RightControl).
if Config.ToggleKey then
    pcall(function()
        local UIS = game:GetService("UserInputService")
        connections[#connections + 1] = UIS.InputBegan:Connect(function(input, gameProcessed)
            if gameProcessed then return end
            if input and input.KeyCode == Config.ToggleKey then EspLib.Toggle() end
        end)
    end)
end

-- Track players that already exist.
for _, plr in ipairs(Players:GetPlayers()) do
    CreateESP(plr)
end

print(string.format("[typeshit.cc private] ESP core %s loaded | native Drawing: %s | players tracked: %d",
    EspLib._VERSION, tostring(USING_NATIVE), #Players:GetPlayers()))
