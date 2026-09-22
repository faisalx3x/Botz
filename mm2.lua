-- games/mm2.lua
-- Called as: moduleFunc()(Window, core)
return function(Window, core)

local HttpService = game:GetService("HttpService")
local SETTINGS_PATH = "WaveScriptBotz/mm2_config.json"

local DEFAULT_SETTINGS = {
    walkSpeed    = 1.0,
    reactionTime = 1.2,
    fleeRadius   = 40,
    coinCollect  = true,
}

local settings = {}
for k, v in pairs(DEFAULT_SETTINGS) do settings[k] = v end

-- Load saved settings
pcall(function()
    if isfile(SETTINGS_PATH) then
        local raw = readfile(SETTINGS_PATH)
        local saved = HttpService:JSONDecode(raw)
        for k, v in pairs(saved) do
            if settings[k] ~= nil then settings[k] = v end
        end
    end
end)

local function saveSettings()
    pcall(function()
        makefolder("WaveScriptBotz")
        writefile(SETTINGS_PATH, HttpService:JSONEncode(settings))
    end)
end

-- ── WindUI Tab ────────────────────────────────────────────────────────
local Tab = Window:Tab({ Title = "MM2" })

local StatusLabel = Tab:Paragraph({ Title = "Status: Idle", Desc = "" })
local RoleLabel   = Tab:Paragraph({ Title = "Role: —", Desc = "" })

local StartButton

StartButton = Tab:Button({ Title = "▶ Start Bot", Callback = function()
    if core.getState() == "RUNNING" then
        core.setState("PAUSED")
        StartButton:SetTitle("▶ Start Bot")
    else
        core.setState("RUNNING")
        StartButton:SetTitle("⏹ Stop Bot")
    end
end })

-- ── Settings Controls ─────────────────────────────────────────────────
Tab:Section({ Title = "Settings" })

Tab:Slider({ Title = "Walk Speed", Value = { Min = 0.8, Max = 1.4, Default = settings.walkSpeed }, Step = 0.05,
    Callback = function(val)
        settings.walkSpeed = val
        saveSettings()
    end
})

Tab:Slider({ Title = "Reaction Time (s)", Value = { Min = 0.5, Max = 3.0, Default = settings.reactionTime }, Step = 0.1,
    Callback = function(val)
        settings.reactionTime = val
        saveSettings()
    end
})

Tab:Slider({ Title = "Flee Radius (studs)", Value = { Min = 15, Max = 80, Default = settings.fleeRadius }, Step = 5,
    Callback = function(val)
        settings.fleeRadius = val
        saveSettings()
    end
})

Tab:Toggle({ Title = "Coin Collect", Value = settings.coinCollect,
    Callback = function(val)
        settings.coinCollect = val
        saveSettings()
    end
})

-- expose settings and helpers for other tasks in this module
local mm2 = {
    settings = settings,
    getSettings = function()
        return {
            walkSpeed    = settings.walkSpeed,
            reactionTime = settings.reactionTime,
            fleeRadius   = settings.fleeRadius,
            coinCollect  = settings.coinCollect,
        }
    end,
}

-- ── Role Detection ────────────────────────────────────────────────────
local _role = "Unknown"
local _roleCallbacks = {}

local function setRole(role)
    _role = role
    RoleLabel:SetTitle("Role: " .. role)
    rconsoleprint("[MM2] Role set to: " .. role .. "\n")
    for _, fn in ipairs(_roleCallbacks) do pcall(fn, role) end
end

local function detectRoleFromTools()
    local char = game.Players.LocalPlayer.Character
    if not char then return "Innocent" end
    for _, tool in ipairs(char:GetChildren()) do
        if not tool:IsA("Tool") then continue end
        if tool.Name == "Knife" then return "Murderer" end
        if tool.Name == "Sheriff Gun" or tool.Name == "Gun" then return "Sheriff" end
    end
    -- Also check backpack
    local bp = game.Players.LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, tool in ipairs(bp:GetChildren()) do
            if not tool:IsA("Tool") then continue end
            if tool.Name == "Knife" then return "Murderer" end
            if tool.Name == "Sheriff Gun" or tool.Name == "Gun" then return "Sheriff" end
        end
    end
    return "Innocent"
end

local function hookRoleEvent()
    local RS = game:GetService("ReplicatedStorage")
    local hooked = false

    pcall(function()
        local gameData = RS:WaitForChild("GameData", 5)
        if gameData then
            local roleVal = gameData:WaitForChild("Role", 3)
            if roleVal and roleVal:IsA("StringValue") then
                setRole(roleVal.Value ~= "" and roleVal.Value or "Innocent")
                roleVal.Changed:Connect(function(val)
                    setRole(val ~= "" and val or "Innocent")
                end)
                hooked = true
            end
        end
    end)

    if not hooked then
        rconsoleprint("[MM2] Role event not found, using tool fallback\n")
        -- Detect role for current character immediately
        setRole(detectRoleFromTools())
        -- Hook future rounds
        game.Players.LocalPlayer.CharacterAdded:Connect(function(char)
            task.wait(3)
            setRole(detectRoleFromTools())
        end)
    end
end

mm2.getRole = function() return _role end
mm2.onRoleChange = function(fn) table.insert(_roleCallbacks, fn) end

task.spawn(hookRoleEvent)

-- ── Innocent Roam + Coin Collect ─────────────────────────────────────

local function getRandomWaypoint()
    -- Sample random position within the map bounds
    -- MM2 maps are typically within ±200 studs of origin
    local x = math.random(-150, 150)
    local z = math.random(-150, 150)
    -- Raycast down from high up to find ground
    local origin = Vector3.new(x, 200, z)
    local result = workspace:Raycast(origin, Vector3.new(0, -250, 0))
    if result then
        return result.Position + Vector3.new(0, 3, 0)
    end
    return Vector3.new(x, 5, z)
end

local function findNearestCoin()
    local hrp = game.Players.LocalPlayer.Character
        and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local nearest, nearestDist = nil, 15 -- only collect within 15 studs

    -- MM2 coins are typically in a Folder named "Coins" or "GameCoins" in Workspace
    local coinsFolder = workspace:FindFirstChild("Coins")
        or workspace:FindFirstChild("GameCoins")
        or workspace:FindFirstChild("coinFolder")
    if not coinsFolder then return nil end

    for _, coin in ipairs(coinsFolder:GetChildren()) do
        if coin:IsA("BasePart") or coin:IsA("Model") then
            local pos
            if coin:IsA("BasePart") then
                pos = coin.Position
            elseif coin.PrimaryPart then
                pos = coin.PrimaryPart.Position
            else
                local bp = coin:FindFirstChildWhichIsA("BasePart", true)
                pos = bp and bp.Position
            end
            if pos then
                local dist = (pos - hrp.Position).Magnitude
                if dist < nearestDist then
                    nearest = pos
                    nearestDist = dist
                end
            end
        end
    end
    return nearest
end

local _gen = 0

local function findMurderer()
    local Players = game:GetService("Players")
    -- We detect murderer by checking who has a Knife tool
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            local char = core.getCharacterOf(player)
            if char then
                if char:FindFirstChild("Knife") then
                    return player
                end
            end
        end
    end
    return nil
end

local function getFleeDest(fromPos, awayFrom)
    -- Find direction away from threat
    local dir = (fromPos - awayFrom).Unit
    -- Try 3 candidate positions in that arc and pick the best (furthest walkable)
    local best = fromPos + dir * 50
    for angle = -30, 30, 30 do
        local rad = math.rad(angle)
        local rotated = Vector3.new(
            dir.X * math.cos(rad) - dir.Z * math.sin(rad),
            0,
            dir.X * math.sin(rad) + dir.Z * math.cos(rad)
        )
        local candidate = fromPos + rotated * 50
        -- Raycast down to find ground
        local r = workspace:Raycast(candidate + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0))
        if r then candidate = r.Position + Vector3.new(0, 3, 0) end
        if (candidate - awayFrom).Magnitude > (best - awayFrom).Magnitude then
            best = candidate
        end
    end
    return best
end

local function findCoverPosition(fromPos, threatPos)
    -- Cast 8 rays outward; find a direction where a part blocks LoS to threat
    for angle = 0, 315, 45 do
        local rad = math.rad(angle)
        local dir = Vector3.new(math.cos(rad), 0, math.sin(rad))
        local candidate = fromPos + dir * 8
        local r = workspace:Raycast(candidate + Vector3.new(0, 5, 0), Vector3.new(0, -10, 0))
        if r then candidate = r.Position + Vector3.new(0, 3, 0) end
        -- Check if this position blocks line of sight to threat
        if not core.hasLineOfSight(candidate + Vector3.new(0, 2.5, 0), threatPos + Vector3.new(0, 2.5, 0)) then
            return candidate
        end
    end
    return nil -- no cover found
end

local function runInnocentBehavior()
    local myGen = _gen
    core.setBaseSpeed(16 * mm2.settings.walkSpeed)

    while myGen == _gen and core.getState() == "RUNNING" and mm2.getRole() == "Innocent" do
        local hrp = game.Players.LocalPlayer.Character
            and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.5) continue end

        local murderer = findMurderer()
        local myPos = hrp.Position

        if murderer then
            local mChar = core.getCharacterOf(murderer)
            local mHrp = mChar and mChar:FindFirstChild("HumanoidRootPart")
            local mPos = mHrp and mHrp.Position

            if not mPos then task.wait(0.3) continue end
            local dist = (myPos - mPos).Magnitude

            if dist <= 15 then
                -- HIDE PHASE
                StatusLabel:SetTitle("Status: Hiding")
                core.stopWalking()
                local coverPos = findCoverPosition(myPos, mPos)
                if coverPos then
                    core.walkTo(coverPos)
                end
                task.wait(0.5)

            elseif dist <= mm2.settings.fleeRadius then
                -- ALERT PHASE — reaction time delay
                StatusLabel:SetTitle("Status: Fleeing")
                task.wait(mm2.settings.reactionTime)
                local fleeDest = getFleeDest(myPos, mPos)
                core.setBaseSpeed(18 * mm2.settings.walkSpeed) -- run faster
                core.walkTo(fleeDest)
                core.setBaseSpeed(16 * mm2.settings.walkSpeed)

            else
                -- ROAM PHASE (murderer exists but is far)
                StatusLabel:SetTitle("Status: Roaming")
                if mm2.settings.coinCollect then
                    local coinPos = findNearestCoin()
                    if coinPos then
                        StatusLabel:SetTitle("Status: Collecting")
                        core.walkTo(coinPos)
                        task.wait(0.2)
                        continue
                    end
                end
                core.walkTo(getRandomWaypoint())
                task.wait(math.random() * 1.0 + 0.3)
            end
        else
            -- ROAM PHASE (no murderer spotted)
            StatusLabel:SetTitle("Status: Roaming")
            if mm2.settings.coinCollect then
                local coinPos = findNearestCoin()
                if coinPos then
                    StatusLabel:SetTitle("Status: Collecting")
                    core.walkTo(coinPos)
                    task.wait(0.2)
                    continue
                end
            end
            core.walkTo(getRandomWaypoint())
            task.wait(math.random() * 1.5 + 0.5)
        end
    end
end

local function runSheriffBehavior()
    local myGen = _gen
    StatusLabel:SetTitle("Status: Hunting")
    core.setBaseSpeed(14 * mm2.settings.walkSpeed) -- cautious speed

    while myGen == _gen and core.getState() == "RUNNING" and mm2.getRole() == "Sheriff" do
        local hrp = game.Players.LocalPlayer.Character
            and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.5) continue end

        local murderer = findMurderer()
        if not murderer then
            -- No murderer found yet — roam to look
            StatusLabel:SetTitle("Status: Searching")
            core.walkTo(getRandomWaypoint())
            task.wait(math.random() * 1.0 + 0.5)
            continue
        end

        local mChar = core.getCharacterOf(murderer)
        local mHrp = mChar and mChar:FindFirstChild("HumanoidRootPart")
        if not mHrp then task.wait(0.3) continue end

        local dist = (hrp.Position - mHrp.Position).Magnitude

        if dist > 20 then
            -- Approach cautiously
            StatusLabel:SetTitle("Status: Closing In")
            core.walkTo(mHrp.Position)

            -- Occasional stop-and-look pause (human noise)
            if math.random() < 0.3 then
                core.stopWalking()
                task.wait(math.random() * 0.8 + 0.2)
            end

        else
            -- Within range — check line of sight then fire
            local fromPos = hrp.Position + Vector3.new(0, 2.5, 0)
            local toPos = mHrp.Position + Vector3.new(0, 2.5, 0)

            if core.hasLineOfSight(fromPos, toPos) then
                StatusLabel:SetTitle("Status: Firing")
                core.stopWalking()

                -- Find and fire the gun tool
                local sChar = game.Players.LocalPlayer.Character
                local gun = sChar and (sChar:FindFirstChild("Sheriff Gun") or sChar:FindFirstChild("Gun"))
                if gun then
                    local handle = gun:FindFirstChild("Handle") or gun:FindFirstChildOfClass("BasePart")
                    local cd = handle and handle:FindFirstChildOfClass("ClickDetector")
                    if cd then
                        fireclickdetector(cd, 0, "MouseClick")
                    end
                end

                task.wait(1.5) -- cooldown after firing
            else
                -- No LoS — reposition
                core.walkTo(mHrp.Position)
            end
        end

        task.wait(0.2)
    end
end

local function findIsolatedTarget()
    local Players = game:GetService("Players")
    local hrp = game.Players.LocalPlayer.Character
        and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local candidates = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            local char = core.getCharacterOf(player)
            if char and not char:FindFirstChild("Knife") and not char:FindFirstChild("Sheriff Gun") then
                local tHrp = char:FindFirstChild("HumanoidRootPart")
                if tHrp then
                    -- Score = distance to nearest other player (higher = more isolated)
                    local isolation = math.huge
                    for _, other in ipairs(Players:GetPlayers()) do
                        if other ~= player and other ~= Players.LocalPlayer then
                            local oChar = core.getCharacterOf(other)
                            local oHrp = oChar and oChar:FindFirstChild("HumanoidRootPart")
                            if oHrp then
                                local d = (tHrp.Position - oHrp.Position).Magnitude
                                if d < isolation then isolation = d end
                            end
                        end
                    end
                    table.insert(candidates, { player = player, isolation = isolation, pos = tHrp.Position })
                end
            end
        end
    end

    if #candidates == 0 then return nil end
    table.sort(candidates, function(a, b) return a.isolation > b.isolation end)
    return candidates[1].player
end

local function findSheriff()
    local Players = game:GetService("Players")
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            local char = core.getCharacterOf(player)
            if char and (char:FindFirstChild("Sheriff Gun") or char:FindFirstChild("Gun")) then
                return player
            end
        end
    end
    return nil
end

local function runMurdererBehavior()
    local myGen = _gen
    StatusLabel:SetTitle("Status: Hunting")
    core.setBaseSpeed(16 * mm2.settings.walkSpeed)

    while myGen == _gen and core.getState() == "RUNNING" and mm2.getRole() == "Murderer" do
        local hrp = game.Players.LocalPlayer.Character
            and game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.5) continue end

        -- Check for Sheriff and avoid if close
        local sheriff = findSheriff()
        if sheriff then
            local sChar = core.getCharacterOf(sheriff)
            local sHrp = sChar and sChar:FindFirstChild("HumanoidRootPart")
            if sHrp then
                local sDist = (hrp.Position - sHrp.Position).Magnitude
                if sDist < 30 then
                    StatusLabel:SetTitle("Status: Evading Sheriff")
                    local fleeDest = getFleeDest(hrp.Position, sHrp.Position)
                    core.walkTo(fleeDest)
                    task.wait(0.3)
                    continue
                end
            end
        end

        -- Find most isolated innocent to target
        local target = findIsolatedTarget()
        if not target then
            StatusLabel:SetTitle("Status: Searching")
            core.walkTo(getRandomWaypoint())
            task.wait(1.0)
            continue
        end

        local tChar = core.getCharacterOf(target)
        local tHrp = tChar and tChar:FindFirstChild("HumanoidRootPart")
        if not tHrp then task.wait(0.3) continue end

        local dist = (hrp.Position - tHrp.Position).Magnitude
        StatusLabel:SetTitle("Status: Stalking")

        if dist > 8 then
            -- Fake direction change occasionally (human-like misdirection)
            if math.random() < 0.15 then
                local angle = math.random() * 2 * math.pi
                local fakeDir = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 10
                core.walkTo(hrp.Position + fakeDir)
                task.wait(0.4)
            end
            core.walkTo(tHrp.Position)
        else
            -- In range — fire knife
            StatusLabel:SetTitle("Status: Striking")
            local mChar = game.Players.LocalPlayer.Character
            local knife = mChar and mChar:FindFirstChild("Knife")
            if knife then
                local handle = knife:FindFirstChild("Handle") or knife:FindFirstChildOfClass("BasePart")
                local cd = handle and handle:FindFirstChildOfClass("ClickDetector")
                if cd then fireclickdetector(cd, 0, "MouseClick") end
            end
            task.wait(1.0)
        end

        task.wait(0.1)
    end
end

local function spawnRoleLoop()
    _gen = _gen + 1
    local role = mm2.getRole()
    if role == "Innocent" then
        task.spawn(function()
            local ok, err = pcall(runInnocentBehavior)
            if not ok then
                rconsolewarn("[MM2] Behavior error: " .. tostring(err))
                StatusLabel:SetTitle("Status: Error — check console")
                StartButton:SetTitle("▶ Start Bot")
                core.setState("IDLE")
            end
        end)
    elseif role == "Sheriff" then
        task.spawn(function()
            local ok, err = pcall(runSheriffBehavior)
            if not ok then
                rconsolewarn("[MM2] Behavior error: " .. tostring(err))
                StatusLabel:SetTitle("Status: Error — check console")
                StartButton:SetTitle("▶ Start Bot")
                core.setState("IDLE")
            end
        end)
    elseif role == "Murderer" then
        task.spawn(function()
            local ok, err = pcall(runMurdererBehavior)
            if not ok then
                rconsolewarn("[MM2] Behavior error: " .. tostring(err))
                StatusLabel:SetTitle("Status: Error — check console")
                StartButton:SetTitle("▶ Start Bot")
                core.setState("IDLE")
            end
        end)
    end
end

mm2.onRoleChange(function(role)
    if core.getState() == "RUNNING" then
        spawnRoleLoop()
    end
end)

core.onState("RUNNING", function()
    spawnRoleLoop()
end)

core.onState("PAUSED", function()
    _gen = _gen + 1
    StatusLabel:SetTitle("Status: Paused")
    StartButton:SetTitle("▶ Start Bot")
    core.stopWalking()
end)

core.onState("STOPPED", function()
    _gen = _gen + 1
    core.stopWalking()
end)

core.onState("IDLE", function()
    StatusLabel:SetTitle("Status: Idle")
    StartButton:SetTitle("▶ Start Bot")
end)

end -- return function
