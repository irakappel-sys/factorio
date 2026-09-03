local function add_count(t, key, amount)
  t[key] = (t[key] or 0) + (amount or 1)
end

local function json_escape(s)
  s = tostring(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\b', '\\b')
  s = s:gsub('\f', '\\f')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  return '"' .. s .. '"'
end

local function is_array(t)
  local max = 0
  local count = 0
  for k, _ in pairs(t) do
    if type(k) ~= 'number' or k < 1 or math.floor(k) ~= k then
      return false, 0
    end
    if k > max then max = k end
    count = count + 1
  end
  return max == count, max
end

local function json_encode(v)
  local tv = type(v)
  if tv == 'nil' then return 'null' end
  if tv == 'boolean' then return v and 'true' or 'false' end
  if tv == 'number' then
    if v ~= v or v == math.huge or v == -math.huge then return 'null' end
    return tostring(v)
  end
  if tv == 'string' then return json_escape(v) end
  if tv ~= 'table' then return json_escape(tostring(v)) end

  local arr, n = is_array(v)
  local out = {}
  if arr then
    for i = 1, n do out[#out + 1] = json_encode(v[i]) end
    return '[' .. table.concat(out, ',') .. ']'
  end

  local keys = {}
  for k, _ in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    out[#out + 1] = json_escape(k) .. ':' .. json_encode(v[k])
  end
  return '{' .. table.concat(out, ',') .. '}'
end

local function safe_recipe_name(entity)
  local ok, recipe = pcall(function() return entity.get_recipe() end)
  if ok and recipe then return recipe.name end
  return nil
end

local function safe_status(entity)
  local ok, value = pcall(function() return entity.status end)
  if ok and value ~= nil then return tostring(value) end
  return nil
end

local function sorted_names_from_map(map)
  local out = {}
  for name, value in pairs(map) do
    if value then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

local function generate_report()
  local force = game.forces['player']
  local report = {
    schema_version = 1,
    tick = game.tick,
    playtime_seconds = game.tick / 60,
    active_mods = {},
    force = {},
    surfaces = {},
    totals = {
      entities_by_name = {},
      entities_by_type = {},
      recipes = {},
      resources = {},
      enemy_entities_by_name = {},
      enemy_entities_by_type = {}
    }
  }

  for name, version in pairs(script.active_mods) do
    report.active_mods[name] = version
  end

  if force then
    local researched = {}
    local enabled_recipes = {}
    for name, tech in pairs(force.technologies) do
      if tech.researched then researched[#researched + 1] = name end
    end
    for name, recipe in pairs(force.recipes) do
      if recipe.enabled then enabled_recipes[#enabled_recipes + 1] = name end
    end
    table.sort(researched)
    table.sort(enabled_recipes)

    local current_research = nil
    local ok, tech = pcall(function() return force.current_research end)
    if ok and tech then current_research = tech.name end

    local progress = nil
    local ok_progress, p = pcall(function() return force.research_progress end)
    if ok_progress then progress = p end

    report.force = {
      name = force.name,
      researched_technologies = researched,
      researched_technology_count = #researched,
      enabled_recipes = enabled_recipes,
      enabled_recipe_count = #enabled_recipes,
      current_research = current_research,
      research_progress = progress
    }
  end

  local interesting_types = {
    ['assembling-machine'] = true,
    ['furnace'] = true,
    ['mining-drill'] = true,
    ['lab'] = true,
    ['beacon'] = true,
    ['roboport'] = true,
    ['train-stop'] = true,
    ['locomotive'] = true,
    ['cargo-wagon'] = true,
    ['fluid-wagon'] = true,
    ['artillery-wagon'] = true,
    ['reactor'] = true,
    ['boiler'] = true,
    ['generator'] = true,
    ['solar-panel'] = true,
    ['accumulator'] = true,
    ['offshore-pump'] = true,
    ['pump'] = true,
    ['storage-tank'] = true,
    ['wall'] = true,
    ['gate'] = true,
    ['ammo-turret'] = true,
    ['electric-turret'] = true,
    ['fluid-turret'] = true,
    ['artillery-turret'] = true,
    ['radar'] = true
  }

  for _, surface in pairs(game.surfaces) do
    local sr = {
      name = surface.name,
      index = surface.index,
      entities_by_name = {},
      entities_by_type = {},
      recipes = {},
      resources = {},
      enemy_entities_by_name = {},
      enemy_entities_by_type = {},
      interesting_entities = {},
      player_entity_bounds = nil
    }

    local min_x, min_y, max_x, max_y = nil, nil, nil, nil

    if force then
      local player_entities = surface.find_entities_filtered{force = force}
      for _, entity in ipairs(player_entities) do
        if entity.valid then
          local name = entity.name
          local etype = entity.type
          add_count(sr.entities_by_name, name, 1)
          add_count(sr.entities_by_type, etype, 1)
          add_count(report.totals.entities_by_name, name, 1)
          add_count(report.totals.entities_by_type, etype, 1)

          local x = entity.position.x
          local y = entity.position.y
          if not min_x or x < min_x then min_x = x end
          if not max_x or x > max_x then max_x = x end
          if not min_y or y < min_y then min_y = y end
          if not max_y or y > max_y then max_y = y end

          if etype == 'assembling-machine' or etype == 'furnace' then
            local recipe = safe_recipe_name(entity)
            if recipe then
              add_count(sr.recipes, recipe, 1)
              add_count(report.totals.recipes, recipe, 1)
            end
          end

          if interesting_types[etype] then
            local detail = {
              name = name,
              type = etype,
              x = x,
              y = y,
              direction = entity.direction,
              status = safe_status(entity)
            }
            local recipe = safe_recipe_name(entity)
            if recipe then detail.recipe = recipe end
            if etype == 'train-stop' then
              local ok_name, backer_name = pcall(function() return entity.backer_name end)
              if ok_name then detail.station_name = backer_name end
            end
            sr.interesting_entities[#sr.interesting_entities + 1] = detail
          end
        end
      end
    end

    if min_x then
      sr.player_entity_bounds = {min_x = min_x, min_y = min_y, max_x = max_x, max_y = max_y}
    end

    local resources = surface.find_entities_filtered{type = 'resource'}
    for _, entity in ipairs(resources) do
      if entity.valid then
        local amount = 0
        local ok_amount, v = pcall(function() return entity.amount end)
        if ok_amount and v then amount = v end
        local entry = sr.resources[entity.name]
        if not entry then
          entry = {entity_count = 0, amount = 0}
          sr.resources[entity.name] = entry
        end
        entry.entity_count = entry.entity_count + 1
        entry.amount = entry.amount + amount

        local total_entry = report.totals.resources[entity.name]
        if not total_entry then
          total_entry = {entity_count = 0, amount = 0}
          report.totals.resources[entity.name] = total_entry
        end
        total_entry.entity_count = total_entry.entity_count + 1
        total_entry.amount = total_entry.amount + amount
      end
    end

    local enemy_force = game.forces['enemy']
    if enemy_force then
      local enemies = surface.find_entities_filtered{force = enemy_force}
      for _, entity in ipairs(enemies) do
        if entity.valid then
          add_count(sr.enemy_entities_by_name, entity.name, 1)
          add_count(sr.enemy_entities_by_type, entity.type, 1)
          add_count(report.totals.enemy_entities_by_name, entity.name, 1)
          add_count(report.totals.enemy_entities_by_type, entity.type, 1)
        end
      end
    end

    report.surfaces[#report.surfaces + 1] = sr
  end

  game.write_file('factory-analysis.json', json_encode(report), false)

  local summary = {}
  summary[#summary + 1] = 'tick=' .. tostring(report.tick)
  summary[#summary + 1] = 'playtime_seconds=' .. tostring(report.playtime_seconds)
  summary[#summary + 1] = 'researched_technology_count=' .. tostring(report.force.researched_technology_count or 0)
  summary[#summary + 1] = 'current_research=' .. tostring(report.force.current_research or '')
  summary[#summary + 1] = ''
  summary[#summary + 1] = '[entities_by_name]'
  local entity_names = {}
  for name, _ in pairs(report.totals.entities_by_name) do entity_names[#entity_names + 1] = name end
  table.sort(entity_names)
  for _, name in ipairs(entity_names) do
    summary[#summary + 1] = name .. '=' .. tostring(report.totals.entities_by_name[name])
  end
  summary[#summary + 1] = ''
  summary[#summary + 1] = '[recipes]'
  local recipe_names = {}
  for name, _ in pairs(report.totals.recipes) do recipe_names[#recipe_names + 1] = name end
  table.sort(recipe_names)
  for _, name in ipairs(recipe_names) do
    summary[#summary + 1] = name .. '=' .. tostring(report.totals.recipes[name])
  end
  summary[#summary + 1] = ''
  summary[#summary + 1] = '[resources]'
  local resource_names = {}
  for name, _ in pairs(report.totals.resources) do resource_names[#resource_names + 1] = name end
  table.sort(resource_names)
  for _, name in ipairs(resource_names) do
    local entry = report.totals.resources[name]
    summary[#summary + 1] = name .. '=' .. tostring(entry.amount) .. ' (' .. tostring(entry.entity_count) .. ' entities)'
  end
  game.write_file('factory-summary.txt', table.concat(summary, '\n') .. '\n', false)
end

local function run_once()
  if storage.factory_analyzer_done then return end
  storage.factory_analyzer_done = true
  local ok, err = pcall(generate_report)
  if not ok then
    game.write_file('factory-analysis-error.txt', tostring(err) .. '\n', false)
  end
end

script.on_init(function()
  storage.factory_analyzer_done = false
end)

script.on_configuration_changed(function()
  storage.factory_analyzer_done = false
end)

script.on_event(defines.events.on_tick, function()
  run_once()
end)
