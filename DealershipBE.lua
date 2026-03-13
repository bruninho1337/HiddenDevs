--[[

Back-end of my dealership system example code!

]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Network = require(ReplicatedStorage.Modules.Utils.Network)
local DebounceHandler = require(ReplicatedStorage.Modules.Utils.DebounceHandler)
local MoneyModule = require(ServerStorage.Modules.Server.MoneyModule)
local NotifyModule = require(ReplicatedStorage.Modules.Utils.NotifyModule)
local CarModule = require(ServerStorage.Modules.Server.CarModule)
local DealershipConfig = require(ReplicatedStorage.Modules.Configs.DealershipConfig)

local CarsModels = ServerStorage.ServerModels.VehicleModels.CarsModels

local GetCars = Network.CreateRemoteFunction("GetCars")
local GetCar = Network.CreateRemoteFunction("GetCar")
local GetPlayerCars = Network.CreateRemoteFunction("GetPlayerCars")
local BuyCar = Network.CreateRemoteFunction("BuyCar")
local SpawnVehicle = Network.CreateRemoteFunction("SpawnVehicle")

local function FindCar(vehName)
	local findCar = CarsModels:FindFirstChild(vehName)
	return findCar
end

local function GetCarData(car)
	local data = {
		Name = car.Name,
	}
	for j, k in pairs(car:GetAttributes()) do
		data[j] = k
	end
	return data
end

local function GetCarsFunc(player)
	local cars = {}
	for i, v in pairs(CarsModels:GetChildren()) do
		local data = GetCarData(v)
		table.insert(cars, data)
	end
	return cars
end

GetCars.OnServerInvoke = GetCarsFunc


local function RemoveScripts(model)
	for _, obj in ipairs(model:GetDescendants()) do
		local exclude = {"Script", "LocalScript"--[[, "ModuleScript"]]}
		if table.find(exclude, obj.ClassName) then
			obj:Destroy()
		end
	end
end

local function GetCarFunc(player, name)
	if typeof(name) ~= "string" then return end
	if string.len(name) >= 150 then return end
	
	local findCar = CarsModels:FindFirstChild(name)
	if not findCar then return end
	
	if not DebounceHandler:Check(player, "GetCar") then return end
	
	DebounceHandler:Add(player, "GetCar")
	
	local clonedCar = findCar:Clone()
	RemoveScripts(clonedCar)
	clonedCar.Parent = ReplicatedStorage
	
	local getData = GetCarData(findCar)
	
	task.delay(0.5, function()
		clonedCar:Destroy()
		DebounceHandler:Remove(player, "GetCar")
	end)
	
	return getData, clonedCar
end

GetCar.OnServerInvoke = GetCarFunc

local function BuyCarFunc(player : Player, vehName : string)
	if typeof(vehName) ~= "string" then return end
	if string.len(vehName) >= 150 then return end
	
	local findCar = CarsModels:FindFirstChild(vehName)
	if not findCar then return end
	
	if not DebounceHandler:Check(player, "BuyCar") then return end
	
	local haveCar = CarModule:HaveCar(player, vehName)
	if haveCar then
		NotifyModule:NotifyError(player, "You already have this vehicle")
		return
	end
	
	DebounceHandler:Add(player, "BuyCar", 0.2)
	
	local foi = MoneyModule:BuySomething(player, tonumber(findCar:GetAttribute("Price")))
	
	if foi then
		CarModule:AddCar(player, vehName)
		NotifyModule:NotifySucess(player, vehName.." successfully purchased")
	else
		NotifyModule:NotifyError(player, "You don't have enough money")
	end

	return foi
end

BuyCar.OnServerInvoke = BuyCarFunc

local function GetPlayerCarsFunc(player : Player)
	if not DebounceHandler:Check(player, "GetPlayerCars") then return end
	DebounceHandler:Add(player, "GetPlayerCars", 0.2)
	local getCars = CarModule:GetCars(player)
	local cars = {}
	for _, carName in pairs(getCars) do
		local v = FindCar(carName)
		if v then
			local data = GetCarData(v)
			table.insert(cars, data)
		end
	end
	return cars
end

GetPlayerCars.OnServerInvoke = GetPlayerCarsFunc


local spawnedCars = {}
local function SpawnVehicleFunc(player : Player, vehName : string, vehSpawnFolder : Folder)
	if typeof(vehName) ~= "string" then return end
	if string.len(vehName) >= 150 then return end
	
	if typeof(vehSpawnFolder) ~= "Instance" then return end
	if not vehSpawnFolder:IsA("Folder") then return end

	local findCar = CarsModels:FindFirstChild(vehName)
	if not findCar then return end
	
	if not DebounceHandler:Check(player, "SpawnVeh") then 
		NotifyModule:NotifyError(player, "Wait a second")
		return 
	end
	
	if not CarModule:HaveCar(player, vehName) then
		NotifyModule:NotifyError(player, "You don't have this vehicle")
		return
	end

	DebounceHandler:Add(player, "SpawnVeh", DealershipConfig.CooldownSpawn)
	
	if not spawnedCars[player] then
		spawnedCars[player] = {}
	end
	
	local qntVeh = #spawnedCars[player]
	if qntVeh >= DealershipConfig.MaxCarSpawnPerPlayer then
		local firstCar = spawnedCars[player][1]
		if firstCar then
			spawnedCars[player][1]:Destroy()
			table.remove(spawnedCars[player], 1)
		end
	end
	
	local car = CarModule:SpawnCar(player, vehName, vehSpawnFolder)
	
	table.insert(spawnedCars[player], car)
	
	NotifyModule:NotifySucess(player, vehName.." successfully spawned")
	
	return car
end

SpawnVehicle.OnServerInvoke = SpawnVehicleFunc

Players.PlayerRemoving:Connect(function(player)
	if spawnedCars[player] then
		for i, v in pairs(spawnedCars[player]) do
			v:Destroy()
		end
		spawnedCars[player] = nil
	end
end)
