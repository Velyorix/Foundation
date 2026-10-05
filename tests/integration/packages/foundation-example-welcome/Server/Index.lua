local context = Foundation.Register(Package, {
	api = "0.1",
	name = "Welcome",
})

context:RegisterCatalog("en", {
	["join.welcome"] = "Welcome, {name}!",
	["homes.count"] = {
		one = "You have {count} home.",
		other = "You have {count} homes.",
	},
})

context:RegisterCatalog("fr", {
	["join.welcome"] = "Bienvenue, {name} !",
	["homes.count"] = {
		one = "Vous avez {count} maison.",
		other = "Vous avez {count} maisons.",
	},
})

Console.Log(context:Translate("join.welcome", { name = "Alex" }))
Console.Log(context:Translate("homes.count", { count = 1 }))
Console.Log(context:Translate("join.welcome", { name = "Alex" }, "fr"))
Console.Log(context:Translate("homes.count", { count = 0 }, "fr"))
Console.Log(context:Translate("homes.count", { count = 3 }, "fr_CA"))
