
local Player = game.Players.LocalPlayer
local PlaceId = game.PlaceId


local Scripts = {
    [12991635726] = "https://raw.githubusercontent.com/FaddedMarket/roblox-scripts/refs/heads/main/Sneaker-Resell-Simulator.lua",
    [16018721946] = "https://raw.githubusercontent.com/FaddedMarket/roblox-scripts/refs/heads/main/SRS-Shoe-Buyer",
	[17321021033] = "https://raw.githubusercontent.com/FaddedMarket/roblox-scripts/refs/heads/main/SRS-Shoe-Buyer",
}

if Scripts[PlaceId] then
    print("Script found for this game, loading...")
    loadstring(game:HttpGet(Scripts[PlaceId]))()
else
    print("No custom script for this game: " .. PlaceId)
end
