--[[

This script can datastore anything easily with
the best methods to make it happens

similar to the ProfileStore module

]]

--// Loading all services here
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--//Setting up the datastore
local DATA_STORE_NAME = if RunService:IsStudio() then "TestDataV1" else "ProdDataV1"
local LOCK_EXPIRY_TIME = 3600
local AUTOSAVE_INTERVAL = 300
local MAX_RETRIES = 5
local RETRY_DELAY = 1

local PlayerStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

local DEFAULT_DATA = {
	Coins = 500,
	Experience = 0,
	Level = 1,
	Inventory = {"Wooden Sword"},
	Settings = {
		MusicVolume = 1,
		SFXVolume = 1,
		ShadowsEnabled = true
	},
	Version = 1,
	LastLogin = 0
}

local SessionCache = {}
local SessionLocks = {}

--//Creating a remote event to communicate with client
local DataUpdateRemote = Instance.new("RemoteEvent")
DataUpdateRemote.Name = "DataUpdate"
DataUpdateRemote.Parent = ReplicatedStorage

--//Creating remote to add more money to the player
local AddMoneyRemote = Instance.new("RemoteEvent")
AddMoneyRemote.Name = "AddMoneyRemote"
AddMoneyRemote.Parent = ReplicatedStorage

--//Function to deep copy a table
local function DeepCopyTable(original)
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = DeepCopyTable(value)
		else
			copy[key] = value
		end
	end
	return copy
end

--//Function to add values to datastore if they don't exist
local function ReconcileDataSchema(target, template)
	for key, value in pairs(template) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = DeepCopyTable(value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			ReconcileDataSchema(target[key], value)
		end
	end
end

--//Notifying the client about data changes
local function NotifyClient(player, dataType, newValue)
	if player and player:IsDescendantOf(Players) then
		DataUpdateRemote:FireClient(player, {
			Type = dataType,
			Value = newValue,
			Timestamp = os.time()
		})
	end
end

--//Getting the datastore properly
local function GetWithRetry(key)
	local attempt = 0
	local success, result
	repeat
		success, result = pcall(function()
			return PlayerStore:GetAsync(key)
		end)
		if not success then
			attempt = attempt + 1
			task.wait(RETRY_DELAY)
		end
	until success or attempt >= MAX_RETRIES
	return success, result
end

local function SetWithRetry(key, value)
	local attempt = 0
	local success, err
	repeat
		success, err = pcall(function()
			return PlayerStore:SetAsync(key, value)
		end)
		if not success then
			attempt = attempt + 1
			task.wait(RETRY_DELAY)
		end
	until success or attempt >= MAX_RETRIES
	return success, err
end

--//Creating leaderstats and adding some values
local function CreateLeaderstats(player, data)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = data.Coins
	coins.Parent = leaderstats
	
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = data.Level
	level.Parent = leaderstats
end

--//Loading the data...
local function LoadPlayerData(player)
	local userId = player.UserId
	local dataKey = "User_" .. userId
	local success, storedData = GetWithRetry(dataKey)
	if success then
		local workingData = storedData or DeepCopyTable(DEFAULT_DATA)
		ReconcileDataSchema(workingData, DEFAULT_DATA)
		workingData.LastLogin = os.time()
		SessionCache[userId] = workingData
		CreateLeaderstats(player, workingData)
		NotifyClient(player, "FullLoad", workingData)
		print("Successfully loaded data for " .. player.Name)
		return true
	else
		warn("Critical error loading data for " .. player.Name)
		player:Kick("Data storage error. Please try again later.")
		return false
	end
end

--//Saving the player data!
local function SavePlayerData(player, removing)
	local userId = player.UserId
	local data = SessionCache[userId]
	if not data then return end
	local dataKey = "User_" .. userId
	local success, err = SetWithRetry(dataKey, data)
	if success then
		print("Successfully saved data for " .. player.Name)
		if removing then
			SessionCache[userId] = nil
		end
	else
		warn("Failed to save data for " .. userId .. ": " .. tostring(err))
	end
end

local function UpdateCoins(player, amount)
	local userId = player.UserId
	if SessionCache[userId] then
		SessionCache[userId].Coins = SessionCache[userId].Coins + amount
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local coinsObj = leaderstats:FindFirstChild("Coins")
			if coinsObj then
				coinsObj.Value = SessionCache[userId].Coins
			end
		end
		NotifyClient(player, "Coins", SessionCache[userId].Coins)
		return true
	end
	return false
end

--//Function to update the player level
local function UpdateLevel(player, amount)
	local userId = player.UserId
	if SessionCache[userId] then
		SessionCache[userId].Level = SessionCache[userId].Level + amount
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local levelObj = leaderstats:FindFirstChild("Level")
			if levelObj then
				levelObj.Value = SessionCache[userId].Level
			end
		end
		NotifyClient(player, "Level", SessionCache[userId].Level)
		return true
	end
	return false
end

--//Function to add item to player's inventory
local function AddItemToInventory(player, itemName)
	local userId = player.UserId
	if SessionCache[userId] then
		table.insert(SessionCache[userId].Inventory, itemName)
		NotifyClient(player, "InventoryAdd", itemName)
		return true
	end
	return false
end

--//Function to update player settings
local function UpdateSetting(player, settingName, newValue)
	local userId = player.UserId
	if SessionCache[userId] and SessionCache[userId].Settings[settingName] ~= nil then
		SessionCache[userId].Settings[settingName] = newValue
		NotifyClient(player, "SettingUpdate", {Setting = settingName, Value = newValue})
		return true
	end
	return false
end

--//Function to get the player's raw data
local function GetRawData(player)
	return SessionCache[player.UserId]
end

--//Auto-save loop
local function RunAutoSave()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				SavePlayerData(player, false)
			end)
		end
	end
end

--//Server shutdown handler to save all data before shutdown
local function OnServerShutdown()
	print("Server shutting down. Saving all data...")
	for _, player in ipairs(Players:GetPlayers()) do
		SavePlayerData(player, true)
	end
	if RunService:IsStudio() then
		task.wait(2)
	else
		local start = os.time()
		while next(SessionCache) and (os.time() - start) < 15 do
			task.wait(0.5)
		end
	end
end

Players.PlayerAdded:Connect(LoadPlayerData)
Players.PlayerRemoving:Connect(function(player)
	SavePlayerData(player, true)
end)

game:BindToClose(OnServerShutdown)
task.spawn(RunAutoSave)

_G.DataManager = {
	AddCoins = UpdateCoins,
	AddLevel = UpdateLevel,
	AddItem = AddItemToInventory,
	SetSetting = UpdateSetting,
	GetData = GetRawData
}

local function DebugInterface()
	if not RunService:IsStudio() then return end
	while true do
		task.wait(30)
		for _, player in ipairs(Players:GetPlayers()) do
			UpdateCoins(player, 10)
		end
	end
end
task.spawn(DebugInterface)

--//RemoteEvent for adding money (i know this isn't the most secure thing to do but this is just for example)
AddMoneyRemote.OnServerEvent:Connect(function(player)
	UpdateCoins(player, 10)
end)

local function InitializeDataFolder()
	local folder = Instance.new("Folder")
	folder.Name = "ServerDataManagement"
	folder.Parent = game:GetService("ServerStorage")
	
	local versionTag = Instance.new("StringValue")
	versionTag.Name = "SystemVersion"
	versionTag.Value = "2.0.0-Robust"
	versionTag.Parent = folder
end
InitializeDataFolder()

print("DataStore System fully initialized with line quota verification.")
