-- init
if not game:IsLoaded() then 
    game.Loaded:Wait()
end

if not syn or not protectgui then
    getgenv().protectgui = function() end
end

local SilentAimSettings = {
    Enabled = true,
    
    ClassName = "Redbox -- Merzt#0001",
    ToggleKey = "RightAlt",
    
    TeamCheck = false,
    VisibleCheck = false, 
    TargetPart = "Head",
    SilentAimMethod = "Raycast",
    
    FOVRadius = 360,
    FOVVisible = true,
    ShowSilentAimTarget = true, 
    
    MouseHitPrediction = false,
    MouseHitPredictionAmount = 0.165,
    HitChance = 100
}

-- variables
getgenv().SilentAimSettings = Settings
local MainFileName = "UniversalSilentAim"
local SelectedFile, FileToSave = "", ""

local Camera = workspace.CurrentCamera
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local GetChildren = game.GetChildren
local GetPlayers = Players.GetPlayers
local WorldToScreen = Camera.WorldToScreenPoint
local WorldToViewportPoint = Camera.WorldToViewportPoint
local GetPartsObscuringTarget = Camera.GetPartsObscuringTarget
local FindFirstChild = game.FindFirstChild
local RenderStepped = RunService.RenderStepped
local GuiInset = GuiService.GetGuiInset
local GetMouseLocation = UserInputService.GetMouseLocation

local resume = coroutine.resume 
local create = coroutine.create

local ValidTargetParts = {"Head", "HumanoidRootPart"}
local PredictionAmount = 0.165

local mouse_box = Drawing.new("Square")
mouse_box.Visible = true 
mouse_box.ZIndex = 999 
mouse_box.Color = Color3.fromRGB(54, 57, 241)
mouse_box.Thickness = 20 
mouse_box.Size = Vector2.new(5, 5)
mouse_box.Filled = true 

local fov_circle = Drawing.new("Circle")
fov_circle.Thickness = 1
fov_circle.NumSides = 100
fov_circle.Radius = 180
fov_circle.Filled = false
fov_circle.Visible = true
fov_circle.ZIndex = 999
fov_circle.Transparency = 1
fov_circle.Color = Color3.fromRGB(54, 57, 241)

local ExpectedArguments = {
    FindPartOnRayWithIgnoreList = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Ray", "table", "boolean", "boolean"
        }
    },
    FindPartOnRayWithWhitelist = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Ray", "table", "boolean"
        }
    },
    FindPartOnRay = {
        ArgCountRequired = 2,
        Args = {
            "Instance", "Ray", "Instance", "boolean", "boolean"
        }
    },
    Raycast = {
        ArgCountRequired = 3,
        Args = {
            "Instance", "Vector3", "Vector3", "RaycastParams"
        }
    }
}

function CalculateChance(Percentage)
    -- // Floor the percentage
    Percentage = math.floor(Percentage)

    -- // Get the chance
    local chance = math.floor(Random.new().NextNumber(Random.new(), 0, 1) * 100) / 100

    -- // Return
    return chance <= Percentage / 100
end


--[[file handling]] do 
    if not isfolder(MainFileName) then 
        makefolder(MainFileName);
    end
    
    if not isfolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId))) then 
        makefolder(string.format("%s/%s", MainFileName, tostring(game.PlaceId)))
    end
end

local Files = listfiles(string.format("%s/%s", "UniversalSilentAim", tostring(game.PlaceId)))

-- functions
local function GetFiles() -- credits to the linoria lib for this function, listfiles returns the files full path and its annoying
	local out = {}
	for i = 1, #Files do
		local file = Files[i]
		if file:sub(-4) == '.lua' then
			-- i hate this but it has to be done ...

			local pos = file:find('.lua', 1, true)
			local start = pos

			local char = file:sub(pos, pos)
			while char ~= '/' and char ~= '\\' and char ~= '' do
				pos = pos - 1
				char = file:sub(pos, pos)
			end

			if char == '/' or char == '\\' then
				table.insert(out, file:sub(pos + 1, start - 1))
			end
		end
	end
	
	return out
end

local function UpdateFile(FileName)
    assert(FileName or FileName == "string", "oopsies");
    writefile(string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName), HttpService:JSONEncode(SilentAimSettings))
end

local function LoadFile(FileName)
    assert(FileName or FileName == "string", "oopsies");
    
    local File = string.format("%s/%s/%s.lua", MainFileName, tostring(game.PlaceId), FileName)
    local ConfigData = HttpService:JSONDecode(readfile(File))
    for Index, Value in next, ConfigData do
        SilentAimSettings[Index] = Value
    end
end

local function getPositionOnScreen(Vector)
    local Vec3, OnScreen = WorldToScreen(Camera, Vector)
    return Vector2.new(Vec3.X, Vec3.Y), OnScreen
end

local function ValidateArguments(Args, RayMethod)
    local Matches = 0
    if #Args < RayMethod.ArgCountRequired then
        return false
    end
    for Pos, Argument in next, Args do
        if typeof(Argument) == RayMethod.Args[Pos] then
            Matches = Matches + 1
        end
    end
    return Matches >= RayMethod.ArgCountRequired
end

local function getDirection(Origin, Position)
    return (Position - Origin).Unit * 1000
end

local function getMousePosition()
    return GetMouseLocation(UserInputService)
end

local function IsPlayerVisible(Player)
    local PlayerCharacter = Player.Character
    local LocalPlayerCharacter = LocalPlayer.Character
    
    if not (PlayerCharacter or LocalPlayerCharacter) then return end 
    
    local PlayerRoot = FindFirstChild(PlayerCharacter, Options.TargetPart.Value) or FindFirstChild(PlayerCharacter, "HumanoidRootPart")
    
    if not PlayerRoot then return end 
    
    local CastPoints, IgnoreList = {PlayerRoot.Position, LocalPlayerCharacter, PlayerCharacter}, {LocalPlayerCharacter, PlayerCharacter}
    local ObscuringObjects = #GetPartsObscuringTarget(Camera, CastPoints, IgnoreList)
    
    return ((ObscuringObjects == 0 and true) or (ObscuringObjects > 0 and false))
end

local function getClosestPlayer()
    if not Options.TargetPart.Value then return end
    local Closest
    local DistanceToMouse
    for _, Player in next, GetPlayers(Players) do
        if Player == LocalPlayer then continue end
        if Toggles.TeamCheck.Value and Player.Team == LocalPlayer.Team then continue end

        local Character = Player.Character
        if not Character then continue end
        
        if Toggles.VisibleCheck.Value and not IsPlayerVisible(Player) then continue end

        local HumanoidRootPart = FindFirstChild(Character, "HumanoidRootPart")
        local Humanoid = FindFirstChild(Character, "Humanoid")
        if not HumanoidRootPart or not Humanoid or Humanoid and Humanoid.Health <= 0 then continue end

        local ScreenPosition, OnScreen = getPositionOnScreen(HumanoidRootPart.Position)
        if not OnScreen then continue end

        local Distance = (getMousePosition() - ScreenPosition).Magnitude
        if Distance <= (DistanceToMouse or Options.Radius.Value or 2000) then
            Closest = ((Options.TargetPart.Value == "Random" and Character[ValidTargetParts[math.random(1, #ValidTargetParts)]]) or Character[Options.TargetPart.Value])
            DistanceToMouse = Distance
        end
    end
    return Closest
end

-- ui creating & handling
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xaxaxaxaxaxaxaxaxa/Libraries/main/UI's/Linoria/Source.lua"))()
Library:SetWatermark("Impulse Cheats")

local Window = Library:CreateWindow("Redbox - Merzt#0001")
local GeneralTab = Window:AddTab("Aimbot")
local GeneralExploitsTab = Window:AddTab("Exploits")
local GeneralVisualsTab = Window:AddTab("Visuals")
local GeneralPlayerTab = Window:AddTab("Player")
local GeneralTeleportsTab = Window:AddTab("Teleports")
local GeneralMapTab = Window:AddTab("Map")
local GeneralMiscTab = Window:AddTab("Misc")
local MainBOX = GeneralTab:AddLeftTabbox("Main") do
local Main = MainBOX:AddTab("Main")
    
    Main:AddToggle("aim_Enabled", {Text = "Enabled"}):AddKeyPicker("aim_Enabled_KeyPicker", {Default = "RightAlt", SyncToggleState = true, Mode = "Toggle", Text = "Enabled", NoUI = false});
    Options.aim_Enabled_KeyPicker:OnClick(function()
        SilentAimSettings.Enabled = not SilentAimSettings.Enabled
        
        Toggles.aim_Enabled.Value = SilentAimSettings.Enabled
        Toggles.aim_Enabled:SetValue(SilentAimSettings.Enabled)
        
        mouse_box.Visible = SilentAimSettings.Enabled
    end)
    
    Main:AddToggle("TeamCheck", {Text = "Team Check", Default = SilentAimSettings.TeamCheck}):OnChanged(function()
        SilentAimSettings.TeamCheck = Toggles.TeamCheck.Value
    end)
    Main:AddToggle("VisibleCheck", {Text = "Visible Check", Default = SilentAimSettings.VisibleCheck}):OnChanged(function()
        SilentAimSettings.VisibleCheck = Toggles.VisibleCheck.Value
    end)
    Main:AddDropdown("TargetPart", {Text = "Target Part", Default = SilentAimSettings.TargetPart, Values = {"Head", "HumanoidRootPart", "Random"}}):OnChanged(function()
        SilentAimSettings.TargetPart = Options.TargetPart.Value
    end)
    Main:AddDropdown("Method", {Text = "Silent Aim Method", Default = SilentAimSettings.SilentAimMethod, Values = {
        "Raycast","FindPartOnRay",
        "FindPartOnRayWithWhitelist",
        "FindPartOnRayWithIgnoreList",
        "Mouse.Hit/Target"
    }}):OnChanged(function() 
        SilentAimSettings.SilentAimMethod = Options.Method.Value 
    end)
    Main:AddSlider('HitChance', {
        Text = 'Hit chance',
        Default = 100,
        Min = 0,
        Max = 100,
        Rounding = 1,
    
        Compact = false,
    })
    Options.HitChance:OnChanged(function()
        SilentAimSettings.HitChance = Options.HitChance.Value
    end)
end

local MiscellaneousBOX = GeneralTab:AddLeftTabbox("Miscellaneous")
local FieldOfViewBOX = GeneralTab:AddLeftTabbox("Field Of View") do
    local Main = FieldOfViewBOX:AddTab("Visuals")
    
    Main:AddToggle("Visible", {Text = "Show FOV Circle"}):AddColorPicker("Color", {Default = Color3.fromRGB(54, 57, 241)}):OnChanged(function()
        fov_circle.Visible = Toggles.Visible.Value
        SilentAimSettings.FOVVisible = Toggles.Visible.Value
    end)
    Main:AddSlider("Radius", {Text = "FOV Circle Radius", Min = 0, Max = 1500, Default = 250, Rounding = 0}):OnChanged(function()
        fov_circle.Radius = Options.Radius.Value
        SilentAimSettings.FOVRadius = Options.Radius.Value
    end)
    Main:AddToggle("MousePosition", {Text = "Show Silent Aim Target"}):AddColorPicker("MouseVisualizeColor", {Default = Color3.fromRGB(54, 57, 241)}):OnChanged(function()
        mouse_box.Visible = Toggles.MousePosition.Value 
        SilentAimSettings.ShowSilentAimTarget = Toggles.MousePosition.Value 
    end)
    local PredictionTab = MiscellaneousBOX:AddTab("Prediction")
    PredictionTab:AddToggle("Prediction", {Text = "Mouse.Hit/Target Prediction"}):OnChanged(function()
        SilentAimSettings.MouseHitPrediction = Toggles.Prediction.Value
    end)
    PredictionTab:AddSlider("Amount", {Text = "Prediction Amount", Min = 0.165, Max = 1, Default = 0.165, Rounding = 3}):OnChanged(function()
        PredictionAmount = Options.Amount.Value
        SilentAimSettings.MouseHitPredictionAmount = Options.Amount.Value
    end)
end

local CreateConfigurationBOX = GeneralTab:AddRightTabbox("Create Configuration") do 
    local Main = CreateConfigurationBOX:AddTab("Create Configuration")
    
    Main:AddInput("CreateConfigTextBox", {Default = "", Numeric = false, Finished = false, Text = "Create Configuration to Create", Tooltip = "Creates a configuration file containing settings you can save and load", Placeholder = "File Name here"}):OnChanged(function()
        if Options.CreateConfigTextBox.Value and string.len(Options.CreateConfigTextBox.Value) ~= "" then 
            FileToSave = Options.CreateConfigTextBox.Value
        end
    end)
    
    Main:AddButton("Create Configuration File", function()
        if FileToSave ~= "" or FileToSave ~= nil then 
            UpdateFile(FileToSave)
        end
    end)
end

local SaveConfigurationBOX = GeneralTab:AddRightTabbox("Save Configuration") do 
    local Main = SaveConfigurationBOX:AddTab("Save Configuration")
    Main:AddDropdown("SaveConfigurationDropdown", {Values = GetFiles(), Text = "Choose Configuration to Save"})
    Main:AddButton("Save Configuration", function()
        if Options.SaveConfigurationDropdown.Value then 
            UpdateFile(Options.SaveConfigurationDropdown.Value)
        end
    end)
end

local LoadConfigurationBOX = GeneralTab:AddRightTabbox("Load Configuration") do 
    local Main = LoadConfigurationBOX:AddTab("Load Configuration")
    
    Main:AddDropdown("LoadConfigurationDropdown", {Values = GetFiles(), Text = "Choose Configuration to Load"})
    Main:AddButton("Load Configuration", function()
        if table.find(GetFiles(), Options.LoadConfigurationDropdown.Value) then
            LoadFile(Options.LoadConfigurationDropdown.Value)
            
            Toggles.TeamCheck:SetValue(SilentAimSettings.TeamCheck)
            Toggles.VisibleCheck:SetValue(SilentAimSettings.VisibleCheck)
            Options.TargetPart:SetValue(SilentAimSettings.TargetPart)
            Options.Method:SetValue(SilentAimSettings.SilentAimMethod)
            Toggles.Visible:SetValue(SilentAimSettings.FOVVisible)
            Options.Radius:SetValue(SilentAimSettings.FOVRadius)
            Toggles.MousePosition:SetValue(SilentAimSettings.ShowSilentAimTarget)
            Toggles.Prediction:SetValue(SilentAimSettings.MouseHitPrediction)
            Options.Amount:SetValue(SilentAimSettings.MouseHitPredictionAmount)
            Options.HitChance:SetValue(SilentAimSettings.HitChance)
        end
    end)
end

local ExploitBox = GeneralExploitsTab:AddLeftTabbox("Exploits") do 
    local Main = ExploitBox:AddTab("Exploits")
    
    Main:AddButton("Kill All (HOLD WAR AXE)", function()
        
        while true do
			for i,v in pairs(game.Players:GetPlayers()) do
				if v and v.Character and v.Character:FindFirstChild("Head") then
					local args = {
						[1] = v.Character.Head,
						[2] = Vector3.new(0, 0, 0),
						[3] = Vector3.new(0, 0, 0),
						[4] = Enum.Material.Plastic,
						[5] = CFrame.new(Vector3.new(0, 0, 0), Vector3.new(0, 0, 0)),
						[6] = game:GetService("Players").LocalPlayer.Character:FindFirstChild("War Axe")
					}

					game:GetService("ReplicatedStorage").Assets.Remotes.hitMelee:FireServer(unpack(args))
				end
			end
		wait(0.5)
		end      
    end)
    
    Main:AddToggle('CuffAura', {
		Text = 'Handcuff Aura',
		Default = false, -- Default value (true / false)
		Tooltip = "Doesn't require cuffs", -- Information shown when you hover over the toggle
	})
    
	
	Toggles.CuffAura:OnChanged(function()
    -- here we get our toggle object & then get its value
		print('Cuff Aura:', Toggles.CuffAura.Value)
		
		_G.Cuff = Toggles.CuffAura.Value
		
		while _G.Cuff do
 
		for i,v in pairs(game.Players:GetPlayers()) do
			if v and v.Character and v.Character:FindFirstChild("Head") then
				if v.Name ~= game.Players.LocalPlayer.Name and v.Character:FindFirstChild("Arrested").Value == false then
					local args = {
						[1] = v.Character
					}
					 
					game:GetService("ReplicatedStorage").Assets.Remotes.cuffsArrest:FireServer(unpack(args))
					end
				end
			wait()
		end
	end
end)
end

local ExploitBox = GeneralExploitsTab:AddRightTabbox("Spawn Menu") do 
    local Main = ExploitBox:AddTab("Spawn Menu")

        Main:AddButton("Grenade (HOLD FRAG GRENADE)", function()
        
        for i,v in pairs(game.Players:GetPlayers()) do
			if v and v.Character and v.Character:FindFirstChild("Head") then
			
				local args = {
					[1] = v.Character,
					[2] = game:GetService("Players").LocalPlayer.Character:FindFirstChild("Frag Grenade")
				}

				game:GetService("ReplicatedStorage").Assets.Remotes.throwGrenade:FireServer(unpack(args))

			end
		end
        
    end)
    
    Main:AddToggle('GSpam', {
		Text = 'Grenade Spam',
		Default = false,
		Tooltip = "Must be holding Frag Grenade.",
	})
    
	
	Toggles.GSpam:OnChanged(function()
		print('Spam Grenades:', Toggles.GSpam.Value)
		
		_G.GS = Toggles.GSpam.Value
		
		while _G.GS do
 
		for i,v in pairs(game.Players:GetPlayers()) do
			if v and v.Character and v.Character:FindFirstChild("Head") then
			
				local args = {
					[1] = v.Character,
					[2] = game:GetService("Players").LocalPlayer.Character:FindFirstChild("Frag Grenade")
				}

				game:GetService("ReplicatedStorage").Assets.Remotes.throwGrenade:FireServer(unpack(args))
			end
			end
			wait()
		end
	end)
end


local MapBox = GeneralMapTab:AddLeftTabbox("Map") do 
    local Main = MapBox:AddTab("Map (CLIENT SIDE)")
    
    Main:AddButton("Delete Map", function()
        
        game.Workspace.Map.mapmisc:Destroy()
		game.Workspace.Map.StreetLights:Destroy()
		game.Workspace.Map.foliage:Destroy()

		game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-21.4498768, 145.897858, -214.090302, 0.998881996, -4.77273066e-09, -0.0472733974, 6.67282185e-09, 1, 4.00358608e-08, 0.0472733974, -4.03065457e-08, 0.998881996)

		local spawn = Instance.new("Part")
		spawn.Parent = game.Workspace
		spawn.Position = Vector3.new(-21.39173698425293, 142.89785766601562, -201.2127685546875)
		spawn.Anchored = true
		spawn.CanCollide = true
		spawn.Transparency = 0
		spawn.Size = Vector3.new(999999, 1, 999999)
        
    end)
end

local PlayerBox = GeneralPlayerTab:AddLeftTabbox("Main") do 
    local Main = PlayerBox:AddTab("Main")
    
    Main:AddButton("F3X", function()
        
        loadstring(game:GetObjects("rbxassetid://6695644299")[1].Source)()
        
    end)
    
    Main:AddButton("NPC Tool", function()
        
        local tool = Instance.new("Tool")
		tool.Name = "Spawn NPC"
		tool.RequiresHandle = false
		tool.Parent = game.Players.LocalPlayer.Backpack

		function onActivation()
		local args = {
		   [1] = game.Players.LocalPlayer:GetMouse().Hit.p
		}
		 
		game:GetService("ReplicatedStorage").Assets.Remotes.spawnDummy:FireServer(unpack(args))
		end

		tool.Activated:Connect(onActivation)
        
    end)
    
    Main:AddButton("Get All Guns", function()
        
			local args = {
				[1] = game:GetService("Players").LocalPlayer.Character,
				[2] = game:GetService("ReplicatedStorage").Assets.Loadout.Primary.AK47
			}

			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))

			local args = {
				[1] = game:GetService("Players").LocalPlayer.Character,
				[2] = game:GetService("ReplicatedStorage").Assets.Loadout.Secondary:FindFirstChild("Beretta M9")
			}

			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))

			local args = {
				[1] = game:GetService("Players").LocalPlayer.Character,
				[2] = game:GetService("ReplicatedStorage").Assets.Loadout.Melee:FindFirstChild("War Axe")
			}

			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))

			local args = {
				[1] = game:GetService("Players").LocalPlayer.Character,
				[2] = game:GetService("ReplicatedStorage").Assets.Loadout.Misc.Cuffs
			}

			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))

			local args = {
				[1] = game:GetService("Players").LocalPlayer.Character,
				[2] = game:GetService("ReplicatedStorage").Assets.Loadout.Primary.M4A1
			}

			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))

			local args = {
			   [1] = game:GetService("Players").LocalPlayer.Character,
			   [2] = game:GetService("ReplicatedStorage").Assets.Loadout.Melee.Halberd
			}

			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))

			local args = {
			   [1] = game:GetService("Players").LocalPlayer.Character,
			   [2] = game:GetService("ReplicatedStorage").Assets.Loadout.Primary["Pump Shotgun"]
			}
			 
			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))

			local args = {
			   [1] = game:GetService("Players").LocalPlayer.Character,
			   [2] = game:GetService("ReplicatedStorage").Assets.Loadout.Misc:FindFirstChild("Frag Grenade")
			}
			 
			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))
			local args = {
			   [1] = game:GetService("Players").LocalPlayer.Character,
			   [2] = game:GetService("ReplicatedStorage").Assets.Loadout.Misc:FindFirstChild("Incendiary Grenade")
			}
			 
			game:GetService("ReplicatedStorage").AddTool:FireServer(unpack(args))
        
	end)
	
	Main:AddButton("Uncuff", function()
        
		game:GetService("Players").LocalPlayer.Character.Arrested.Value = false
        
	end)
end

local Teleports = GeneralTeleportsTab:AddLeftTabbox("Teleports") do 
local Main = Teleports:AddTab("Teleports")

	Main:AddButton("Teleport Sewers", function()
	
	local plr = game:GetService("Players").LocalPlayer
	local character = plr.Character
	
	character.HumanoidRootPart.CFrame = CFrame.new(-20.9391174, 104.704521, -301.2724, 0.999983251, -3.63300714e-08, 0.00579067506, 3.55516221e-08, 1, 1.34534048e-07, -0.00579067506, -1.34325916e-07, 0.999983251)

end)

	Main:AddButton("Teleport Farm", function()
	
	local plr = game:GetService("Players").LocalPlayer
	local character = plr.Character
	
	character.HumanoidRootPart.CFrame = CFrame.new(-76.0004807, 164.152695, -829.835693, -0.999944568, 4.59734162e-09, 0.0105311209, 3.46335916e-09, 1, -1.07697417e-07, -0.0105311209, -1.07654969e-07, -0.999944568)
end)

	Main:AddButton("Teleport Shop", function()
	
	local plr = game:GetService("Players").LocalPlayer
	local character = plr.Character
	
	character.HumanoidRootPart.CFrame = CFrame.new(190.336609, 164.23999, -273.42865, -0.0068814056, -9.67158584e-08, 0.999976337, 3.10456159e-08, 1, 9.69317924e-08, -0.999976337, 3.17119095e-08, -0.0068814056)
end)

	Main:AddButton("Teleport Outside Subway", function()
	
	local plr = game:GetService("Players").LocalPlayer
	local character = plr.Character
	
	character.HumanoidRootPart.CFrame = CFrame.new(160.844803, 164.240723, -461.791656, 0.0122261178, 5.50175372e-08, 0.999925256, -4.5753616e-08, 1, -5.44622161e-08, -0.999925256, -4.50843345e-08, 0.0122261178)
end)

	Main:AddButton("Teleport Subway", function()
	
	local plr = game:GetService("Players").LocalPlayer
	local character = plr.Character
	
	character.HumanoidRootPart.CFrame = CFrame.new(161.930481, 136.839996, -505.417511, 0.012924416, -1.07781588e-07, -0.999916494, -7.46766062e-08, 1, -1.08755827e-07, 0.999916494, 7.60759704e-08, 0.012924416)
end)
end



local VisualsBox = GeneralVisualsTab:AddLeftTabbox("Visuals") do 
local Main = VisualsBox:AddTab("Visuals")

Main:AddButton("ESP", function()
	
	local Players = game:GetService("Players")
	local CoreGui = game:GetService("CoreGui")

	if _G.HighlightESP then return end
	_G.HighlightESP = true

	-- Constants:
	local LocalPlayer = Players.LocalPlayer
	local ProtectInstance = syn and syn.protect_gui or function(instance) end

	-- Variables:
	local ESPs = {}

	-- Functions:
	local function onPlayerAdded(player: Player)
	-- Creates Highlight:
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.RobloxLocked = true
	ProtectInstance(highlight)
	ESPs[player] = highlight
	highlight.Parent = CoreGui

	-- Update ESP:
	local function onCharacterAdded(character: Model)
	   highlight.Adornee = character
	end

	player.CharacterAdded:Connect(onCharacterAdded)
	do -- Initialize current character
	   local character = player.Character
	   if character then onCharacterAdded(character) end
	end
	end

	local function onPlayerRemoving(player: Player)
	-- Destroys Highlight:
	local highlight = ESPs[player]
	highlight:Destroy()
	ESPs[player] = nil
	end

	-- Listeners:
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Actions:
	for i,v in ipairs(Players:GetPlayers()) do
	if v ~= LocalPlayer then
	   onPlayerAdded(v)
	end
	end

end)
end


local MiscBox = GeneralMiscTab:AddLeftTabbox("Misc") do 
local Main = MiscBox:AddTab("Misc")

Main:AddButton("Rejoin", function()
	
	local queueonteleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
	local httprequest = (syn and syn.request) or http and http.request or http_request or (fluxus and fluxus.request) or request
	local httpservice = game:GetService('HttpService')
	queueonteleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/Merzttt/dawg/main/dawggy.lua'))()")
	
	local ts = game:GetService("TeleportService")
	local p = game:GetService("Players").LocalPlayer

	ts:Teleport(game.PlaceId, p)

end)

Main:AddButton("Server Hop", function()
	
	local queueonteleport = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
	local httprequest = (syn and syn.request) or http and http.request or http_request or (fluxus and fluxus.request) or request
	local httpservice = game:GetService('HttpService')
	queueonteleport("loadstring(game:HttpGet('https://raw.githubusercontent.com/Merzttt/dawg/main/dawggy.lua'))()")
	
    local Http = game:GetService("HttpService")
	local TPS = game:GetService("TeleportService")
	local Api = "https://games.roblox.com/v1/games/"

	local _place = game.PlaceId
	local _servers = Api.._place.."/servers/Public?sortOrder=Desc&limit=100"
	function ListServers(cursor)
	   local Raw = game:HttpGet(_servers .. ((cursor and "&cursor="..cursor) or ""))
	   return Http:JSONDecode(Raw)
	end

	local Server, Next; repeat
	   local Servers = ListServers(Next)
	   Server = Servers.data[1]
	   Next = Servers.nextPageCursor
	until Server

	TPS:TeleportToPlaceInstance(_place,Server.id,game.Players.LocalPlayer)

	end)
		
    
    Main:AddButton("Unload", function()
        
        Library:Unload()
        script:Destroy()
        
    end)
end

resume(create(function()
    RenderStepped:Connect(function()
        if Toggles.MousePosition.Value and Toggles.aim_Enabled.Value then
            if getClosestPlayer() then 
                local Root = getClosestPlayer().Parent.PrimaryPart or getClosestPlayer()
                local RootToViewportPoint, IsOnScreen = WorldToViewportPoint(Camera, Root.Position);
                -- using PrimaryPart instead because if your Target Part is "Random" it will flicker the square between the Target's Head and HumanoidRootPart (its annoying)
                
                mouse_box.Visible = IsOnScreen
                mouse_box.Position = Vector2.new(RootToViewportPoint.X, RootToViewportPoint.Y)
            else 
                mouse_box.Visible = false 
                mouse_box.Position = Vector2.new()
            end
        end
        
        if Toggles.Visible.Value then 
            fov_circle.Visible = Toggles.Visible.Value
            fov_circle.Color = Options.Color.Value
            fov_circle.Position = getMousePosition()
        end
    end)
end))

-- hooks
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(...)
    local Method = getnamecallmethod()
    local Arguments = {...}
    local self = Arguments[1]
    local chance = CalculateChance(SilentAimSettings.HitChance)
    if Toggles.aim_Enabled.Value and self == workspace and not checkcaller() and chance == true then
        if Method == "FindPartOnRayWithIgnoreList" and Options.Method.Value == Method then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithIgnoreList) then
                local A_Ray = Arguments[2]

                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)

                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif Method == "FindPartOnRayWithWhitelist" and Options.Method.Value == Method then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRayWithWhitelist) then
                local A_Ray = Arguments[2]

                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)

                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif (Method == "FindPartOnRay" or Method == "findPartOnRay") and Options.Method.Value:lower() == Method:lower() then
            if ValidateArguments(Arguments, ExpectedArguments.FindPartOnRay) then
                local A_Ray = Arguments[2]

                local HitPart = getClosestPlayer()
                if HitPart then
                    local Origin = A_Ray.Origin
                    local Direction = getDirection(Origin, HitPart.Position)
                    Arguments[2] = Ray.new(Origin, Direction)

                    return oldNamecall(unpack(Arguments))
                end
            end
        elseif Method == "Raycast" and Options.Method.Value == Method then
            if ValidateArguments(Arguments, ExpectedArguments.Raycast) then
                local A_Origin = Arguments[2]

                local HitPart = getClosestPlayer()
                if HitPart then
                    Arguments[3] = getDirection(A_Origin, HitPart.Position)

                    return oldNamecall(unpack(Arguments))
                end
            end
        end
    end
    return oldNamecall(...)
end))

local oldIndex = nil 
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, Index)
    if self == Mouse and not checkcaller() and Toggles.aim_Enabled.Value and Options.Method.Value == "Mouse.Hit/Target" and getClosestPlayer() then
        local HitPart = getClosestPlayer()
         
        if Index == "Target" or Index == "target" then 
            return HitPart
        elseif Index == "Hit" or Index == "hit" then 
            return ((Toggles.Prediction.Value and (HitPart.CFrame + (HitPart.Velocity * PredictionAmount))) or (not Toggles.Prediction.Value and HitPart.CFrame))
        elseif Index == "X" or Index == "x" then 
            return self.X 
        elseif Index == "Y" or Index == "y" then 
            return self.Y 
        elseif Index == "UnitRay" then 
            return Ray.new(self.Origin, (self.Hit - self.Origin).Unit)
        end
    end

    return oldIndex(self, Index)
end))
