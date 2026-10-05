local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Daily Rewards",
})

local S = Foundation.Schema

local settings = context:Config({
	fields = {
		{
			key = "enabled",
			schema = S.Boolean(),
			default = true,
			description = "Give a reward on the first join of each day.",
			reload = "hot",
		},
		{
			key = "reward.amount",
			schema = S.Integer({ min = 1, max = 100000 }),
			default = 250,
			description = "Amount of money given.",
			reload = "hot",
		},
		{
			key = "reward.message",
			schema = S.String({ min = 1, max = 120 }),
			default = "Here is your daily reward!",
			description = "Message shown with the reward.",
		},
	},
})

local function describe()
	if not settings:Get("enabled") then
		return "daily rewards are disabled"
	end
	return string.format("daily reward: %d (%s)", settings:Get("reward.amount"), settings:Get("reward.message"))
end

Console.Log(describe())

settings:OnChange(function()
	Console.Log(describe())
end)
