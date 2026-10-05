-- Specification of foundation/config.toml. is_locale: core/i18n.lua IsLocale.
return function(S, messages, is_locale)
	return {
		path = "foundation/config.toml",
		version = 1,
		migrations = {},
		header_key = "config.template.header",
		sections = {
			{
				fields = {
					{
						key = "language",
						schema = S:Custom("foundation:locale", function(value)
							if is_locale(value) then
								return true
							end
							return false, messages:Format("reason.locale_format")
						end),
						default = "en",
						reload = "hot",
						comment_key = "config.template.language",
					},
				},
			},
			{
				name = "log",
				fields = {
					{
						key = "level",
						schema = S:Enum({ "debug", "info", "warning", "error" }),
						default = "info",
						reload = "hot",
						comment_key = "config.template.log_level",
					},
					{
						key = "debug_categories",
						schema = S:List(S:String({ min = 1, max = 64 }), { max = 64 }),
						default = {},
						reload = "hot",
						comment_key = "config.template.debug_categories",
					},
				},
			},
		},
	}
end
