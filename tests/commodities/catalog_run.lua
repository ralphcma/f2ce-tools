-- Real bundled base prices and selection/price-scan code; isolated transport.
local root = tostring(arg and arg[1] or ".")
local real_open = io.open
local f = assert(real_open(root.."/src/resources/commodities.json", "rb"))
local bytes = f:read("*a"); f:close()
local records = {}
-- Only the simple commodity records are needed by this JSON stand-in.
for name, price in bytes:gmatch('"name"%s*:%s*"([^"]+)"[^\r\n]-"basePrice"%s*:%s*(%d+)') do
    records[#records+1] = {name=name,basePrice=tonumber(price)}
end
assert(#records==67, "fixture must contain the complete bundled catalog")
local sent, timers, data
local passed, failed=0,0
local function eq(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1; print("PASS "..name)
    else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
function getMudletHomeDir() return "fixture" end
function f2t_debug_log() end
function cecho() end
function f2t_table_count_keys(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
function f2t_check_rank_requirement() return true end
function f2t_check_tool_requirement() return true end
function tempTimer(_,fn) timers[#timers+1]=fn; return #timers end
function f2t_price_check_commodity(name,cb)
    sent[#sent+1]=name; cb(name, {}, {commodity=name})
end
local function reset()
    sent,timers={},{}
    data={groups={{commodities={}}}}
    for _,row in ipairs(records) do
        table.insert(data.groups[1].commodities,{name=row.name,basePrice=row.basePrice})
    end
    yajl={to_value=function() return data end}
    io.open=function(path,mode)
        if path=="fixture/f2ce-tools/commodities.json" then
            return {read=function() return bytes end,close=function() end}
        end
        return real_open(path,mode)
    end
    dofile(root.."/src/scripts/commodities/commodity_resolver.lua")
    dofile(root.."/src/scripts/commodities/price_all.lua")
end
local function drain() while #timers>0 do table.remove(timers,1)() end end
local expected={"NanoFabrics","TQuarks","BioComponents","Artifacts","Monopoles","Controllers",
    "Droids","LanzariK","Woods","Firewalls","Libraries","Powerpacks","Generators","BioChips",
    "Crystals","Furs","Spices","Pharmaceuticals","Katydidics","Gold","Tracers"}

test("top 21 use fixed catalog prices and include both 600ig ties",function()
    reset(); local selected=assert(f2t_get_highest_base_commodities(21)); eq(#selected,21)
    eq(table.concat(selected,","),table.concat(expected,",")); eq(#f2t_get_all_commodities(),67)
    selected[1]="changed"; eq(f2t_get_highest_base_commodities(21)[1],"NanoFabrics")
end)
test("selected scan requests exactly 21 without changing manual price all",function()
    reset(); local count; local selected=f2t_get_highest_base_commodities(21)
    assert(f2t_price_get_all_data(function(rows) count=#rows end, selected))
    selected[2]="cereals"; drain(); eq(count,21); eq(#sent,21)
    for i,name in ipairs(expected) do eq(sent[i],name:lower()) end
    sent={}; assert(f2t_price_get_all_data(function(rows) count=#rows end)); drain()
    eq(count,67); eq(#sent,67)
end)
test("malformed base price stops selection instead of backfilling unknown goods",function()
    reset(); data.groups[1].commodities[1].basePrice=nil
    eq(f2t_get_highest_base_commodities(21),nil)
end)
test("incomplete catalog cannot silently select fewer than 21",function()
    reset(); while #data.groups[1].commodities>20 do table.remove(data.groups[1].commodities) end
    eq(f2t_get_highest_base_commodities(21),nil)
end)
test("invalid selected price scans send nothing",function()
    reset()
    for _,selection in ipairs({{}, {"bogus"}, {"Gold","gold"}}) do
        eq(f2t_price_get_all_data(function() error("unexpected callback") end,selection),false)
    end
    eq(#sent,0)
end)
print(string.format("RESULT %d passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end
