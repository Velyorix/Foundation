local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Kits",
})

local S = Foundation.Schema

local Kit = S.Record({
	name = S.String({ min = 1, max = 32 }),
	items = S.List(S.String({ min = 1 }), { min = 1, max = 10 }),
	cooldown = S.Optional(S.Integer({ min = 0 }), 300),
})

local kits = {}

local function define_kit(id, definition)
	local key, key_error = Foundation.Keys.Parse(id, context:GetId())
	if not key then
		return nil, key_error
	end
	local kit, err = S.Validate(Kit, definition)
	if not kit then
		return nil, err
	end
	kits[key] = kit
	return key
end

local key = define_kit("starter", { name = "Starter", items = { "pistol", "bandage" } })
Console.Log("defined %s, cooldown %d s", key, kits[key].cooldown)

local _, err = define_kit("builder", { name = "", items = { "hammer", 42 } })
Console.Log("rejected: %s", err.message)
for _, problem in ipairs(err.details.problems) do
	Console.Log("- %s", problem.message)
end

local _, key_error = define_kit("Bad Kit", { name = "Bad", items = { "stick" } })
Console.Log("rejected: %s", key_error.message)
