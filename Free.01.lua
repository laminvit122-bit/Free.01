local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shooter = ReplicatedStorage:WaitForChild("Shooter", 20)

local LP = Players.LocalPlayer
local GEN = (rawget(_G, "ANON_SHOOTER_GEN") or 0) + 1
rawset(_G, "ANON_SHOOTER_GEN", GEN)

local function alive()
    return rawget(_G, "ANON_SHOOTER_GEN") == GEN
end

local S = { gp = false, sb = false, passes = 0, err = "" }
local O = {}
local pass
local tearing = false

local function req(name)
    local inst = Shooter and Shooter:FindFirstChild(name)
    if not inst then
        return nil
    end
    local ok, m = pcall(require, inst)
    if ok and type(m) == "table" then
        return m
    end
    return nil
end

local function find_pass()
    -- the shared ctx table every panel module keeps holds the game's own pass object
    local order = { "MinigunTrial", "WeaponsPanel", "SandboxPanel", "HUD", "SideBar", "MainMenu", "Sandbox", "TracerPass" }
    for _, name in ipairs(order) do
        local m = req(name)
        if m then
            for _, fn in pairs(m) do
                if type(fn) == "function" then
                    for i = 1, 40 do
                        local ok, v = pcall(debug.getupvalue, fn, i)
                        if not ok then
                            break
                        end
                        if type(v) == "table" then
                            local c = rawget(v, "ctx")
                            if type(c) == "table" then
                                local p = rawget(c, "pass")
                                if type(p) == "table" and type(rawget(p, "isOwned")) == "function" then
                                    return p
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function persist()
    if tearing then
        return
    end
    pcall(function()
        workspace:SetAttribute("ANON_GP", S.gp)
        workspace:SetAttribute("ANON_SB", S.sb)
    end)
end

local function apply_gp(on)
    pass = pass or find_pass()
    if pass then
        if on then
            if not O.is_owned then
                O.is_owned = pass.isOwned
            end
            pass.isOwned = function()
                return true
            end
        elseif O.is_owned then
            pass.isOwned = O.is_owned
        end
    end

    local gate = req("PassGate")
    if gate then
        if on then
            if not O.gate then
                O.gate = { wait = gate.wait, owned = gate.owned, confirm = gate.confirm }
            end
            gate.wait = function()
                return true
            end
            gate.owned = function()
                return true
            end
            gate.confirm = function()
                return true
            end
        elseif O.gate then
            gate.wait, gate.owned, gate.confirm = O.gate.wait, O.gate.owned, O.gate.confirm
        end
    end

    local tracer = req("TracerPass")
    if tracer and type(tracer.isOwned) == "function" then
        if on then
            if not O.tracer then
                O.tracer = tracer.isOwned
            end
            tracer.isOwned = function()
                return true
            end
        elseif O.tracer then
            tracer.isOwned = O.tracer
        end
    end

    S.gp = on
    S.passes = on and 7 or 0
    persist()
end

local function apply_sb(on)
    local sandbox = req("Sandbox")
    if sandbox then
        pcall(sandbox.forceOwned, on)
        pcall(sandbox.setActive, on)
        S.sb = on and sandbox.active == true
    end
    persist()
end

local COL = {
    bg = Color3.fromRGB(17, 19, 23),
    panel = Color3.fromRGB(25, 28, 34),
    line = Color3.fromRGB(48, 53, 64),
    text = Color3.fromRGB(228, 233, 241),
    dim = Color3.fromRGB(128, 136, 151),
    accent = Color3.fromRGB(255, 59, 92),
    on = Color3.fromRGB(61, 220, 132),
    off = Color3.fromRGB(40, 44, 54),
}
local FONT = Enum.Font.GothamBold
local W = 216
local H_HEAD = 30
local ROW_H = 28
local H_FOOT = 18
local H_OPEN = H_HEAD + ROW_H * 2 + H_FOOT + 8

local gui
local frame
local body
local chevron
local footer
local rows = {}
local open = true

local function label(parent, text, size, color, x, y, w, h)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Text = text
    t.Font = FONT
    t.TextSize = size
    t.TextColor3 = color
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextYAlignment = Enum.TextYAlignment.Center
    t.Position = UDim2.fromOffset(x, y)
    t.Size = UDim2.fromOffset(w, h)
    t.Parent = parent
    return t
end

local function tween(inst, props)
    TweenService:Create(inst, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function refresh()
    for key, row in pairs(rows) do
        local on = S[key] == true
        row.track.BackgroundColor3 = on and COL.on or COL.off
        tween(row.knob, { Position = UDim2.fromOffset(on and 18 or 3, 3) })
        row.label.TextColor3 = on and COL.text or COL.dim
        row.dot.BackgroundColor3 = on and COL.on or COL.off
    end
    if footer then
        footer.Text = S.gp and ("GAMEPASSES " .. S.passes .. " · SANDBOX " .. (S.sb and "ON" or "OFF")) or "idle"
        footer.TextColor3 = (S.gp or S.sb) and COL.dim or COL.off
    end
    if gui then
        gui:SetAttribute("gp", S.gp)
        gui:SetAttribute("sb", S.sb)
    end
end

local function add_row(y, text, key, setter)
    local row = Instance.new("TextButton")
    row.Name = "row_" .. key
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0
    row.AutoButtonColor = false
    row.Text = ""
    row.Position = UDim2.fromOffset(8, y)
    row.Size = UDim2.new(1, -16, 0, ROW_H)
    row.Parent = body

    local dot = Instance.new("Frame")
    dot.BackgroundColor3 = COL.off
    dot.BorderSizePixel = 0
    dot.Position = UDim2.fromOffset(2, ROW_H / 2 - 3)
    dot.Size = UDim2.fromOffset(6, 6)
    dot.Parent = row
    local dot_corner = Instance.new("UICorner")
    dot_corner.CornerRadius = UDim.new(0.5, 0)
    dot_corner.Parent = dot

    local lab = label(row, text, 11, COL.dim, 14, 0, 130, ROW_H)

    local track = Instance.new("Frame")
    track.BackgroundColor3 = COL.off
    track.BorderSizePixel = 0
    track.AnchorPoint = Vector2.new(1, 0.5)
    track.Position = UDim2.new(1, -2, 0.5, 0)
    track.Size = UDim2.fromOffset(34, 18)
    track.Parent = row
    local track_corner = Instance.new("UICorner")
    track_corner.CornerRadius = UDim.new(0.5, 0)
    track_corner.Parent = track

    local knob = Instance.new("Frame")
    knob.BackgroundColor3 = Color3.fromRGB(236, 240, 246)
    knob.BorderSizePixel = 0
    knob.Position = UDim2.fromOffset(3, 3)
    knob.Size = UDim2.fromOffset(12, 12)
    knob.Parent = track
    local knob_corner = Instance.new("UICorner")
    knob_corner.CornerRadius = UDim.new(0.5, 0)
    knob_corner.Parent = knob

    rows[key] = { label = lab, dot = dot, track = track, knob = knob }

    row.MouseButton1Click:Connect(function()
        if not alive() then
            return
        end
        setter(not S[key])
        refresh()
    end)
end

local drag = { active = false, moved = false, start = Vector2.zero, abs = Vector2.zero }
local dragged = false

local function viewport()
    local cam = workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

local function clamp_topleft(pos, size)
    local view = viewport()
    return Vector2.new(
        math.clamp(pos.X, 0, math.max(0, view.X - size.X)),
        math.clamp(pos.Y, 0, math.max(0, view.Y - size.Y))
    )
end

local function set_open(state)
    open = state
    body.Visible = open
    chevron.Text = open and "▾" or "▸"
    local h = open and H_OPEN or H_HEAD
    if dragged then
        local p = clamp_topleft(Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset), Vector2.new(W, h))
        frame.Position = UDim2.fromOffset(p.X, p.Y)
    end
    tween(frame, { Size = UDim2.fromOffset(W, h) })
end

local function build()
    local pg = LP:FindFirstChild("PlayerGui") or LP:WaitForChild("PlayerGui")
    for _, c in ipairs(pg:GetChildren()) do
        if c:IsA("ScreenGui") and c.Name == "ANON_Shooter" then
            c:Destroy()
        end
    end

    gui = Instance.new("ScreenGui")
    gui.Name = "ANON_Shooter"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 200
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = pg

    frame = Instance.new("Frame")
    frame.Name = "Panel"
    frame.BackgroundColor3 = COL.panel
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.fromScale(0.5, 0.5)
    frame.Size = UDim2.fromOffset(W, H_OPEN)
    frame.Parent = gui
    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(0, 8)
    fc.Parent = frame
    local fs = Instance.new("UIStroke")
    fs.Color = COL.line
    fs.Thickness = 1
    fs.Parent = frame

    local head = Instance.new("TextButton")
    head.Name = "Head"
    head.BackgroundTransparency = 1
    head.BorderSizePixel = 0
    head.AutoButtonColor = false
    head.Text = ""
    head.Size = UDim2.new(1, 0, 0, H_HEAD)
    head.Parent = frame

    local dot = Instance.new("Frame")
    dot.BackgroundColor3 = COL.accent
    dot.BorderSizePixel = 0
    dot.Position = UDim2.fromOffset(10, H_HEAD / 2 - 3)
    dot.Size = UDim2.fromOffset(6, 6)
    dot.Parent = head
    local dc = Instance.new("UICorner")
    dc.CornerRadius = UDim.new(0.5, 0)
    dc.Parent = dot

    label(head, "ANON", 12, COL.text, 22, 0, 100, H_HEAD)

    chevron = label(head, "▾", 12, COL.dim, W - 26, 0, 16, H_HEAD)
    chevron.TextXAlignment = Enum.TextXAlignment.Center

    body = Instance.new("Frame")
    body.Name = "Body"
    body.BackgroundTransparency = 1
    body.Position = UDim2.fromOffset(0, H_HEAD)
    body.Size = UDim2.fromOffset(W, ROW_H * 2 + H_FOOT + 8)
    body.Parent = frame

    add_row(0, "ALL GAMEPASSES", "gp", apply_gp)
    add_row(ROW_H, "SANDBOX MODE", "sb", apply_sb)

    footer = label(body, "idle", 10, COL.off, 10, ROW_H * 2 + 2, W - 20, H_FOOT)

    head.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        drag.active = true
        drag.moved = false
        drag.start = Vector2.new(input.Position.X, input.Position.Y)
        drag.abs = frame.AbsolutePosition
    end)

    head.MouseButton1Click:Connect(function()
        if drag.moved then
            drag.moved = false
            return
        end
        set_open(not open)
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not drag.active then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.start
        if delta.Magnitude > 4 then
            drag.moved = true
        end
        if drag.moved then
            if not dragged then
                frame.AnchorPoint = Vector2.new(0, 0)
                frame.Position = UDim2.fromOffset(drag.abs.X, drag.abs.Y)
                dragged = true
            end
            local p = clamp_topleft(drag.abs + delta, frame.AbsoluteSize)
            frame.Position = UDim2.fromOffset(p.X, p.Y)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            drag.active = false
        end
    end)
end

local function namecall_hook()
    if STATE and STATE.namecallHook then
        return STATE.namecallHook("UserOwnsGamePassAsync", function()
            if S.gp then
                return true
            end
        end)
    end
    local mt = getrawmetatable(game)
    local old = mt.__namecall
    setreadonly(mt, false)
    local hooked
    hooked = newcclosure(function(self, ...)
        if getnamecallmethod() == "UserOwnsGamePassAsync" and S.gp then
            return true
        end
        return old(self, ...)
    end)
    mt.__namecall = hooked
    setreadonly(mt, true)
    return function()
        setreadonly(mt, false)
        if mt.__namecall == hooked then
            mt.__namecall = old
        end
        setreadonly(mt, true)
    end
end

local function teardown()
    tearing = true
    apply_sb(false)
    apply_gp(false)
    if gui then
        gui:Destroy()
        gui = nil
    end
    rawset(getgenv and getgenv() or _G, "ANON_SHOOTER", nil)
end

local function main()
    build()
    namecall_hook()
    refresh()

    local prev_gp = workspace:GetAttribute("ANON_GP") == true
    local prev_sb = workspace:GetAttribute("ANON_SB") == true
    if prev_gp then
        apply_gp(true)
    end
    if prev_sb then
        apply_sb(true)
    end
    refresh()

    local cam = workspace.CurrentCamera
    if cam then
        cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if dragged then
                local p = clamp_topleft(Vector2.new(frame.Position.X.Offset, frame.Position.Y.Offset), frame.AbsoluteSize)
                frame.Position = UDim2.fromOffset(p.X, p.Y)
            else
                frame.Position = UDim2.fromScale(0.5, 0.5)
            end
        end)
    end

    rawset(getgenv and getgenv() or _G, "ANON_SHOOTER", {
        state = S,
        set_gp = function(on)
            apply_gp(on == true)
            refresh()
        end,
        set_sb = function(on)
            apply_sb(on == true)
            refresh()
        end,
        open = function(state)
            set_open(state ~= false)
        end,
        pass = function()
            return pass
        end,
        teardown = teardown,
    })

    print("[ANON] panel ready · pass=" .. tostring(pass ~= nil))
end

if STATE and STATE.onCleanup then
    STATE.onCleanup(teardown)
end

task.spawn(main)
