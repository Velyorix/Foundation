local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local S = Foundation.Schema

context:DefineEvent("purchase", {
	fields = { item = S.String({ min = 1 }), price = S.Integer({ min = 0 }) },
	mutable = { "price" },
	cancellable = true,
})

Package.Export("EventsFixture", {
	Purchase = function(item, price)
		local event = context:Emit("purchase", { item = item, price = price })
		return event:Get("price"), event:IsCancelled()
	end,
})
