--!strict
-- Publishes a place file over an existing place of a game, as File > Publish
-- As in Studio does, through Roblox's Open Cloud Place Publishing API:
--
--     lune run tools/publish-place <place file> <universe id> <place id>
--
-- The API key comes from the environment variable ROBLOX_PLACE_API_KEY. It
-- needs the universe-places API with the Write operation on that game. The
-- API leaves EditableImage, EditableMesh, PartOperation, SurfaceAppearance
-- and BaseWrap as they were, so a place with them is published from Studio;
-- the demo place has none.

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local KEY_VARIABLE = "ROBLOX_PLACE_API_KEY"
-- Says so when the key expires within this many days, to renew it in time.
local EXPIRY_WARNING_DAYS = 14

local path, universeId, placeId = process.args[1], process.args[2], process.args[3]
if not (path and universeId and placeId) then
	error("usage: lune run tools/publish-place <place file> <universe id> <place id>", 0)
end
if not (universeId:match("^%d+$") and placeId:match("^%d+$")) then
	error("the universe id and the place id are numbers", 0)
end
local key = process.env[KEY_VARIABLE]
if not key or key == "" then
	error(`set {KEY_VARIABLE} to an API key with universe-places Write on the game`, 0)
end
local contentType = if path:match("%.rbxlx$")
	then "application/xml"
	elseif path:match("%.rbxl$") then "application/octet-stream"
	else error("the place file is a .rbxl or a .rbxlx", 0)
local place = fs.readFile(path)

-- Anyone may ask about a key; the key goes in the body.
local introspect = net.request({
	url = "https://apis.roblox.com/api-keys/v1/introspect",
	method = "POST",
	headers = { ["Content-Type"] = "application/json" },
	body = serde.encode("json", { apiKey = key }),
})
if not introspect.ok then
	error(`could not check the key: {introspect.statusCode} {introspect.body}`, 0)
end
local info = serde.decode("json", introspect.body)
if not info.enabled or info.expired then
	error("the key is disabled or has expired; renew it on the Creator Dashboard", 0)
end
if typeof(info.expirationTimeUtc) == "string" then
	-- Seconds come with seven decimals, which the parser does not take.
	local expiry = DateTime.fromIsoDate(info.expirationTimeUtc:sub(1, 19) .. "Z")
	local days = (expiry.unixTimestamp - DateTime.now().unixTimestamp) / 86400
	if days < EXPIRY_WARNING_DAYS then
		print(`note: the key expires in {math.floor(days)} days`)
	end
end

local response = net.request({
	url = `https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published`,
	method = "POST",
	headers = { ["x-api-key"] = key, ["Content-Type"] = contentType },
	body = place,
})
if not response.ok then
	error(`publishing failed: {response.statusCode} {response.body}`, 0)
end
local version = serde.decode("json", response.body).versionNumber
print(`published {path} to place {placeId}, version {version}`)
