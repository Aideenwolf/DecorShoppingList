local ADDON, ns = ...
ns.Plugins = ns.Plugins or {}

function ns:RegisterPlugin(name, plugin)
  if not name or type(plugin) ~= "table" then return end
  ns.Plugins[name] = plugin
end

function ns:InitPlugins(addon)
  for name, plugin in pairs(ns.Plugins) do
    if type(plugin.IsAvailable) == "function" and not plugin:IsAvailable(addon) then
      -- skip
    else
      if type(plugin.OnInit) == "function" then
        pcall(plugin.OnInit, plugin, addon)
      end
    end
  end
end
