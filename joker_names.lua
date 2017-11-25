local function parsefile(fname)
  local file = io.open(fname, "r")
  local data = {}
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
  JokerNames.name_styles = {
    "N",
    "N, K",
    "N (K)"
  }
  JokerNames.localized_name_styles = {}
  JokerNames.settings = {
    use_custom_names = false,
    force_names = 1,
    name_style = 1
  }
  JokerNames.original_joker_names = {}
  
  function JokerNames:create_name(name, original_name, style)
    if not original_name then
      return name
    end
    local style = self.name_styles[style] or self.name_styles[self.settings.name_style] or self.name_styles[1]
    return style:gsub("N", name):gsub("K", original_name)
  end
  
  function JokerNames:save()
    local file = io.open(self.save_path .. "joker_names.txt", "w+")
    if file then
      file:write(json.encode(self.settings))
      file:close()
    end
  end

  function JokerNames:load()
    local file = io.open(self.save_path .. "joker_names.txt", "r")
    if file then
      local data = json.decode(file:read("*all")) or {}
      file:close()
      for k, v in pairs(data) do
        self.settings[k] = v
      end
    end
    self:load_names()
  end
  
  function JokerNames:load_names()
    if self.settings.use_custom_names then
      self.names = parsefile(self.save_path .. "custom_joker_names.txt")
      if not self.names.male or not self.names.female or #self.names.male == 0 or self.names.female == 0 then
        self.names = nil
      end
    end
    if not self.settings.use_custom_names or not self.names then
      self.names = {
        male = parsefile(self.mod_path .. "data/names_m.json"),
        female = parsefile(self.mod_path .. "data/names_f.json")
      }
    end
  end
  
  function JokerNames:check_create_custom_name_file()
    local file = io.open(JokerNames.save_path .. "custom_joker_names.txt", "r")
    local created = false
    if not file then
      file = io.open(JokerNames.save_path .. "custom_joker_names.txt", "w+")
      file:write(json.encode({
        male = { table.random(JokerNames.names.male), table.random(JokerNames.names.male) },
        female = { table.random(JokerNames.names.female), table.random(JokerNames.names.female) }
      }))
      local title = managers.localization:to_upper_text("JokerNames_menu_information")
      local message = managers.localization:text("JokerNames_menu_information_text")
      created = true
    end
    file:close()
    return created
  end
  
  function JokerNames:create_localized_name_styles(loc_manager)
    local tbl = {}
    self.localized_name_styles = {}
    for i, _ in ipairs(self.name_styles) do
      local key = "JokerNames_menu_name_style_" .. i
      table.insert(self.localized_name_styles, key)
      tbl[key] = self:create_name(loc_manager:text("JokerNames_menu_name_style_name"), loc_manager:text("JokerNames_menu_name_style_keepers_name"), i)
    end
    loc_manager:add_localized_strings(tbl)
  end
  
  JokerNames:load()

end


if RequiredScript == "lib/managers/group_ai_states/groupaistatebase" then

  local convert_hostage_to_criminal_original = GroupAIStateBase.convert_hostage_to_criminal
  function GroupAIStateBase:convert_hostage_to_criminal(unit, peer_unit)
    if not alive(unit) then
      return
    end
    if Keepers then
      local player_unit = peer_unit or managers.player:player_unit()
      local is_local = player_unit == managers.player:player_unit()
      local peer_id = player_unit:network():peer():id()
      local is_empty_name = Keepers.joker_names[peer_id] == "My Joker" or Keepers.joker_names[peer_id] == ""
      JokerNames.original_joker_names[peer_id] = JokerNames.original_joker_names[peer_id] or Keepers:GetJokerNameByPeer(peer_id)
      
      if player_unit and (is_local or JokerNames.settings.force_names == 2 and is_empty_name or JokerNames.settings.force_names == 3) then
        
        local new_name = table.random(unit:base()._tweak_table:find("female") and JokerNames.names.female or JokerNames.names.male)
        Keepers.joker_names[peer_id] = JokerNames:create_name(new_name, JokerNames.original_joker_names[peer_id])
        
        if is_local and Keepers.settings.send_my_joker_name then
          for peer_id, peer in pairs(managers.network:session():peers()) do
            if Keepers:IsModdedClient(peer_id) and peer:unit() ~= player_unit then
              LuaNetworking:SendToPeer(peer_id, "Keepers!", new_name)
            end
          end
        end
        
      end
    end
    return convert_hostage_to_criminal_original(self, unit, peer_unit)
  end

end


if RequiredScript == "lib/managers/menumanager" then

  Hooks:Add("LocalizationManagerPostInit", "LocalizationManagerPostInitJokerNames", function(loc)
    loc:load_localization_file(JokerNames.mod_path .. "loc/english.txt")
    for _, filename in pairs(file.GetFiles(JokerNames.mod_path .. "loc/") or {}) do
      local str = filename:match("^(.*).txt$")
      if str and Idstring(str) and Idstring(str):key() == SystemInfo:language():key() then
        loc:load_localization_file(JokerNames.mod_path .. "loc/" .. filename)
        break
      end
    end
    JokerNames:create_localized_name_styles(loc)
  end)

  local menu_id_main = "JokerNamesMenu"
  Hooks:Add("MenuManagerSetupCustomMenus", "MenuManagerSetupCustomMenusJokerNames", function(menu_manager, nodes)
    MenuHelper:NewMenu(menu_id_main)
  end)

  Hooks:Add("MenuManagerPopulateCustomMenus", "MenuManagerPopulateCustomMenusJokerNames", function(menu_manager, nodes)
    
    JokerNames:load()
    
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

    MenuHelper:AddToggle({
      id = "use_custom_names",
      title = "JokerNames_menu_use_custom_names",
      desc = "JokerNames_menu_use_custom_names_desc",
      callback = "JokerNames_custom_names",
      value = KillFeed.settings.use_custom_names,
      menu_id = menu_id_main,
      priority = 99
    })
    
    MenuHelper:AddMultipleChoice({
      id = "name_style",
      title = "JokerNames_menu_name_style",
      desc = "JokerNames_menu_name_style_desc",
      callback = "JokerNames_value",
      value = JokerNames.settings.name_style,
      items = JokerNames.localized_name_styles,
      menu_id = menu_id_main,
      priority = 98
    })
    
    MenuHelper:AddMultipleChoice({
      id = "force_names",
      title = "JokerNames_menu_force_names",
      desc = "JokerNames_menu_force_names_desc",
      callback = "JokerNames_value",
      value = JokerNames.settings.force_names,
      items = { "JokerNames_menu_force_names_never", "JokerNames_menu_force_names_empty", "JokerNames_menu_force_names_always" },
      menu_id = menu_id_main,
      priority = 97
    })
    
  end)

  Hooks:Add("MenuManagerBuildCustomMenus", "MenuManagerBuildCustomMenusPlayerJokerNames", function(menu_manager, nodes)
    nodes[menu_id_main] = MenuHelper:BuildMenu(menu_id_main)
    MenuHelper:AddMenuItem(nodes["blt_options"], menu_id_main, "JokerNames_menu_main_name", "JokerNames_menu_main_desc")
  end)
  
end
