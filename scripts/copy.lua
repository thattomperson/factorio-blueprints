-- Deep copy for plain data tables (blueprint entity tables). The runtime stage has no table.deepcopy.
local function deepcopy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[deepcopy(k)] = deepcopy(v) end
  return result
end
return deepcopy
