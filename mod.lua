if not HopLib then
	return
end

if not Keepers then
	Keepers = {
		impostor = true,
		settings = {},
		joker_names = {},
		get_covered_interactable_units = function () return {} end,
		get_joker_name_by_peer = function (self, peer_id) return self.joker_names[peer_id] end,
		get_special_objective = function () end,
		is_unit_interactable = function () end
	}
end

Keepers.joker_name_max_length = 255

local function parsefile(fname)
	local file = io.open(fname, "r")
	local data
	if file then
		data = json.decode(file:read("*all"))
		file:close()
	end
	return data
end

if not JokerNames then

	_G.JokerNames = {}
	JokerNames.mod_path = ModPath
	JokerNames.save_path = SavePath
	JokerNames.original_name_empty = {}
	JokerNames.settings = {
		use_custom_names = false,
		force_names = 1,
		custom_name_style = "%N"
	}

	function JokerNames:create_name(info)
		local name_style = self.settings.custom_name_style
		local name_table = info:is_female() and self.names.female or self.names.male
		local original_name = Keepers.settings.my_joker_name or ""
		return name_style:gsub("%%N", function () return table.random(name_table) end):gsub("%%S", function () return table.random(self.names.surnames) end):gsub("%%K", original_name):gsub("%%T", info:name())
	end

	function JokerNames:save()
		local file = io.open(self.save_path .. "joker_names.txt", "w+")
		if file then
			file:write(json.encode(self.settings))
			file:close()
		end
	end

	function JokerNames:load()
		for k, v in pairs(parsefile(self.save_path .. "joker_names.txt") or {}) do
			self.settings[k] = v
		end
		self:load_names()
	end

	function JokerNames:load_names()
		self.names = {
			male = parsefile(self.mod_path .. "data/names_m.json"),
			female = parsefile(self.mod_path .. "data/names_f.json"),
			surnames = parsefile(self.mod_path .. "data/surnames.json")
		}
		if self.settings.use_custom_names then
			for k, v in pairs(parsefile(self.save_path .. "custom_joker_names.txt") or {}) do
				self.names[k] = v
			end
		end
	end

	function JokerNames:check_create_custom_name_file()
		local file = io.open(JokerNames.save_path .. "custom_joker_names.txt", "r")
		local created = false
		if not file then
			local example_names = {}
			for k, v in pairs(JokerNames.names) do
				example_names[k] = { table.random(v), table.random(v) }
			end
			file = io.open(JokerNames.save_path .. "custom_joker_names.txt", "w+")
			file:write(json.encode(example_names))
			created = true
		end
		file:close()
		return created
	end

	function JokerNames:set_joker_name(peer_id, unit)
		if not alive(unit) then
			return
		end

		if Keepers.impostor then
			unit:base().kpr_minion_owner_peer_id = peer_id
		end

		Keepers.joker_names[peer_id] = self:create_name(HopLib:unit_info_manager():get_info(unit, nil, true))
	end

	function JokerNames:check_peer_name_override(peer_id, unit)
		if JokerNames.settings.force_names < 2 then
			return
		end
		if JokerNames.original_name_empty[peer_id] == nil then
			JokerNames.original_name_empty[peer_id] = Keepers.joker_names[peer_id] == "My Joker" or Keepers.joker_names[peer_id] == ""
		end
		if JokerNames.original_name_empty[peer_id] or self.settings.force_names == 3 then
			self:set_joker_name(peer_id, unit)
		end
	end

	JokerNames:load()

end


if RequiredScript == "lib/units/interactions/interactionext" then

	-- Handle joker name setting
	local interact_original = IntimitateInteractionExt.interact
	function IntimitateInteractionExt:interact(player, ...)

		if self.tweak_data == "hostage_convert" and self:can_interact(player) then

			local peer_id = player:network():peer():id()

			JokerNames:set_joker_name(peer_id, self._unit)

			if Keepers.settings.send_my_joker_name then
				LuaNetworking:SendToPeers("Keepers!", Keepers.joker_names[peer_id])
			end

		end

		return interact_original(self, player, ...)
	end

	-- Handle name overrides (as host)
	local sync_interacted_original = IntimitateInteractionExt.sync_interacted
	function IntimitateInteractionExt:sync_interacted(peer, player, status, ...)

		if self.tweak_data == "hostage_convert" then
			JokerNames:check_peer_name_override(peer and peer:id() or managers.network:session():local_peer():id(), self._unit)
		end

		return sync_interacted_original(self, peer, player, status, ...)
	end

end


if RequiredScript == "lib/network/handlers/unitnetworkhandler" then

	-- Handle name overrides (as client)
	local mark_minion_original = UnitNetworkHandler.mark_minion
	function UnitNetworkHandler:mark_minion(unit, minion_owner_peer_id, ...)

		if minion_owner_peer_id ~= managers.network:session():local_peer():id() then
			JokerNames:check_peer_name_override(minion_owner_peer_id, unit)
		end

		return mark_minion_original(self, unit, minion_owner_peer_id, ...)
	end

end


if RequiredScript == "lib/managers/menumanager" then

	Hooks:Add("LocalizationManagerPostInit", "LocalizationManagerPostInitJokerNames", function(loc)

		HopLib:load_localization(JokerNames.mod_path .. "loc/", loc)

	end)

	local menu_id_main = "JokerNamesMenu"
	Hooks:Add("MenuManagerSetupCustomMenus", "MenuManagerSetupCustomMenusJokerNames", function(menu_manager, nodes)
		MenuHelper:NewMenu(menu_id_main)
	end)

	Hooks:Add("MenuManagerPopulateCustomMenus", "MenuManagerPopulateCustomMenusJokerNames", function(menu_manager, nodes)

		MenuCallbackHandler.JokerNames_toggle = function(self, item)
			JokerNames.settings[item:name()] = (item:value() == "on")
			JokerNames:save()
		end

		MenuCallbackHandler.JokerNames_value = function(self, item)
			JokerNames.settings[item:name()] = item:value()
			JokerNames:save()
		end

		MenuCallbackHandler.JokerNames_custom_names = function(self, item)
			MenuCallbackHandler.JokerNames_toggle(self, item)
			if JokerNames.settings[item:name()] and JokerNames:check_create_custom_name_file() then
				local title = managers.localization:to_upper_text("JokerNames_menu_information")
				local message = managers.localization:text("JokerNames_menu_information_text")
				QuickMenu:new(title, message, {text = managers.localization:text("menu_ok"), is_cancel_button = true }, true)
			end
			JokerNames:load_names()
		end

		MenuHelper:AddInput({
			id = "custom_name_style",
			title = "JokerNames_menu_name_style",
			desc = "JokerNames_menu_name_style_desc",
			callback = "JokerNames_value",
			value = JokerNames.settings.custom_name_style,
			menu_id = menu_id_main,
			priority = 99
		})

		MenuHelper:AddMultipleChoice({
			id = "force_names",
			title = "JokerNames_menu_force_names",
			desc = "JokerNames_menu_force_names_desc",
			callback = "JokerNames_value",
			value = JokerNames.settings.force_names,
			items = { "JokerNames_menu_force_names_never", "JokerNames_menu_force_names_empty", "JokerNames_menu_force_names_always" },
			menu_id = menu_id_main,
			priority = 96
		})

		MenuHelper:AddToggle({
			id = "use_custom_names",
			title = "JokerNames_menu_use_custom_names",
			desc = "JokerNames_menu_use_custom_names_desc",
			callback = "JokerNames_custom_names",
			value = JokerNames.settings.use_custom_names,
			menu_id = menu_id_main,
			priority = 90
		})

	end)

	Hooks:Add("MenuManagerBuildCustomMenus", "MenuManagerBuildCustomMenusPlayerJokerNames", function(menu_manager, nodes)
		nodes[menu_id_main] = MenuHelper:BuildMenu(menu_id_main)
		MenuHelper:AddMenuItem(nodes["blt_options"], menu_id_main, "JokerNames_menu_main_name", "JokerNames_menu_main_desc")
	end)

end
