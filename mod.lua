if Keepers then
	Keepers.joker_name_max_length = 255
end

local function parsefile(fname)
	return io.file_is_readable(fname) and io.load_as_json(fname) or {}
end

if not JokerNames then

	_G.JokerNames = {}
	JokerNames.mod_path = ModPath
	JokerNames.save_path = SavePath
	JokerNames.original_name_empty = {}
	JokerNames.settings = {
		add_labels = true,
		custom_name_style = "%N",
		force_names = 1,
		use_custom_names = false
	}

	function JokerNames:create_name(info)
		local name_style = self.settings.custom_name_style
		local name_table = info:is_female() and self.names.female or self.names.male
		local original_name = Keepers and Keepers.settings.my_joker_name or ""
		return name_style:gsub("%%N", function () return table.random(name_table) end):gsub("%%S", function () return table.random(self.names.surnames) end):gsub("%%K", original_name):gsub("%%T", info:name())
	end

	function JokerNames:save()
		io.save_as_json(self.settings, self.save_path .. "joker_names.txt")
	end

	function JokerNames:load()
		table.replace(self.settings, parsefile(self.save_path .. "joker_names.txt"))
		self:load_names()
	end

	function JokerNames:load_names()
		self.names = {
			male = parsefile(self.mod_path .. "data/names_m.json"),
			female = parsefile(self.mod_path .. "data/names_f.json"),
			surnames = parsefile(self.mod_path .. "data/surnames.json")
		}
		if self.settings.use_custom_names then
			local names = parsefile(self.save_path .. "custom_joker_names.txt")
			self.names.male = names.male and #names.male > 0 and names.male or self.names.male
			self.names.female = names.female and #names.female > 0 and names.female or self.names.female
			self.names.surnames = names.surnames and #names.surnames > 0 and names.surnames or self.names.surnames
		end
	end

	function JokerNames:check_create_custom_name_file()
		if io.file_is_readable(JokerNames.save_path .. "custom_joker_names.txt") then
			return
		end

		local example_names = {}
		for k, v in pairs(JokerNames.names) do
			example_names[k] = { table.random(v), table.random(v) }
		end

		return io.save_as_json(example_names, JokerNames.save_path .. "custom_joker_names.txt")
	end

	function JokerNames:set_joker_name(peer_id, unit)
		if not alive(unit) then
			return
		end

		local name = self:create_name(HopLib:unit_info_manager():get_info(unit, nil, true))
		unit:base().joker_name = name
		if Keepers then
			Keepers.joker_names[peer_id] = name
		end
	end

	function JokerNames:check_peer_name_override(peer_id, unit)
		if JokerNames.settings.force_names < 2 then
			return
		end
		if JokerNames.original_name_empty[peer_id] == nil then
			JokerNames.original_name_empty[peer_id] = not Keepers or Keepers.joker_names[peer_id] == "My Joker" or Keepers.joker_names[peer_id] == ""
		end
		if JokerNames.original_name_empty[peer_id] or self.settings.force_names == 3 then
			self:set_joker_name(peer_id, unit)
		end
	end

	JokerNames:load()

	Hooks:Add("HopLibOnMinionAdded", "HopLibOnMinionAddedJokerNames", function (unit, player_unit)
		if not unit:base().joker_name or unit:unit_data().name_label_id or not JokerNames.settings.add_labels then
			return
		end

		unit:unit_data().name_label_id = managers.hud:_add_name_label({
			name = unit:base().joker_name,
			unit = unit
		})
	end)

	Hooks:Add("HopLibOnMinionRemoved", "HopLibOnMinionRemovedJokerNames", function (unit)
		if unit:unit_data().name_label_id then
			managers.hud:_remove_name_label(unit:unit_data().name_label_id)
			unit:unit_data().name_label_id = nil
		end
	end)

	Hooks:Add("LocalizationManagerPostInit", "LocalizationManagerPostInitJokerNames", function (loc)
		HopLib:load_localization(JokerNames.mod_path .. "loc/", loc)
	end)

	Hooks:Add("MenuManagerBuildCustomMenus", "MenuManagerBuildCustomMenusJokerNames", function (menu_manager, nodes)
		local menu_id_main = "JokerNamesMenu"

		MenuHelper:NewMenu(menu_id_main)

		MenuCallbackHandler.JokerNames_toggle = function (self, item)
			JokerNames.settings[item:name()] = (item:value() == "on")
		end

		MenuCallbackHandler.JokerNames_value = function (self, item)
			JokerNames.settings[item:name()] = item:value()
		end

		MenuCallbackHandler.JokerNames_custom_names = function (self, item)
			MenuCallbackHandler.JokerNames_toggle(self, item)
			if JokerNames.settings[item:name()] and JokerNames:check_create_custom_name_file() then
				local title = managers.localization:to_upper_text("JokerNames_menu_information")
				local message = managers.localization:text("JokerNames_menu_information_text")
				QuickMenu:new(title, message, {text = managers.localization:text("menu_ok"), is_cancel_button = true }, true)
			end
			JokerNames:load_names()
		end

		MenuCallbackHandler.JokerNames_save = function ()
			JokerNames:save()
		end

		if not Keepers then
			MenuHelper:AddToggle({
				id = "add_labels",
				title = "JokerNames_menu_add_labels",
				desc = "JokerNames_menu_add_labels_desc",
				callback = "JokerNames_toggle",
				value = JokerNames.settings.add_labels,
				menu_id = menu_id_main,
				priority = 100
			})
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

		nodes[menu_id_main] = MenuHelper:BuildMenu(menu_id_main, { back_callback = "JokerNames_save" })
		MenuHelper:AddMenuItem(nodes["blt_options"], menu_id_main, "JokerNames_menu_main_name", "JokerNames_menu_main_desc")
	end)

end

if RequiredScript == "lib/units/interactions/interactionext" then

	-- Handle joker name setting
	Hooks:PreHook(IntimitateInteractionExt, "interact", "interact_joker_names", function (self, player)
		if self.tweak_data == "hostage_convert" and self:can_interact(player) then
			JokerNames:set_joker_name(player:network():peer():id(), self._unit)
			if not Keepers or Keepers.settings.send_my_joker_name then
				LuaNetworking:SendToPeers("Keepers!", self._unit:base().joker_name)
			end
		end
	end)

	-- Handle name overrides (as host)
	Hooks:PreHook(IntimitateInteractionExt, "sync_interacted", "sync_interacted_joker_names", function (self, peer)
		if self.tweak_data == "hostage_convert" then
			JokerNames:check_peer_name_override(peer and peer:id() or managers.network:session():local_peer():id(), self._unit)
		end
	end)

elseif RequiredScript == "lib/network/handlers/unitnetworkhandler" then

	-- Handle name overrides (as client)
	Hooks:PreHook(UnitNetworkHandler, "mark_minion", "mark_minion_joker_names", function (self, unit, minion_owner_peer_id)
		if minion_owner_peer_id ~= managers.network:session():local_peer():id() then
			JokerNames:check_peer_name_override(minion_owner_peer_id, unit)
		end
	end)

end
