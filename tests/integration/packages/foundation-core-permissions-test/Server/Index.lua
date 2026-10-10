local context = Foundation.Register(Package, { api = Foundation.API_VERSION })
local NODE = "foundation-core-permissions-test.admin"

context:DeclarePermission(NODE, { description = "Administer the test", default = "nobody" })

local function explain(subject)
	local result = Foundation.Permissions.Explain(subject, NODE)
	return tostring(result.allowed) .. ":" .. result.source .. (result.package and (":" .. result.package) or "")
end

local suite = FoundationTest.Suite("core-permissions")

suite:Test("an external provider package decides for the subjects it knows", function()
	FoundationTest.True(Server.IsPackageLoaded("foundation-permissions-provider-fixture"))
	FoundationTest.Equal(explain("alex"), "true:provider:foundation-permissions-provider-fixture")
	FoundationTest.Equal(explain("sam"), "false:default")
end)

suite:Test("attachments still come first", function()
	local handle = context:AttachPermission("alex", NODE, false)
	FoundationTest.Equal(explain("alex"), "false:attachment:foundation-core-permissions-test")
	handle:Release()
end)

suite:Do(function()
	Server.UnloadPackage("foundation-permissions-provider-fixture")
end)
suite:Wait(300)

suite:Test("without the provider, the declared default applies again", function()
	FoundationTest.Equal(explain("alex"), "false:default")
end)

suite:Test("each change of provider is audited", function()
	local path = "foundation/audit/audit-" .. os.date("!%Y-%m-%d", math.floor(Server.GetTime() / 1000)) .. ".log"
	local file = File(path)
	local text = file:Read()
	file:Close()
	local count = 0
	for _ in text:gmatch('"action":"foundation:permissions/provider"') do
		count = count + 1
	end
	FoundationTest.Equal(count, 2, text)
end)

suite:Run()
