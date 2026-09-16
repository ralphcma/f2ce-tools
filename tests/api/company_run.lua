-- Synthetic fixture matching Factory::Display's complete protocol; no profile data.
local Mock=dofile("tests/api/mock_adapter.lua")
local root=arg[1] or "."
dofile(root.."/src/scripts/api/v1.lua")
dofile(root.."/src/scripts/api/services.lua")
dofile(root.."/src/scripts/api/company.lua")
dofile(root.."/src/scripts/api/company_depot.lua")
dofile(root.."/src/scripts/factory/display_parser.lua")
dofile(root.."/src/scripts/factory/depot_parser.lua")
local API=F2CE.API.v1
local fixture=[[
Sample Ltd: Firewalls Production Facility #1
  Location: Example World  Status: Running
  Finance:
    Working Capital: -1,000ig  Top Up Level: 100,000ig
    Income: 40,000ig  Expenditure: 3,025ig
    Profit last company accounting period: -200ig
  Structure:
    Efficiency: 100/100
    Storage: 750/1500 tons available
  Workers:
    Required: 150  Hired: 150  Wages: 40ig
  Inputs:
    Semiconductors   Required: 20   Available: 5
  Output:
    Stored: 750 tons of Firewalls
    Dispose of Firewalls to exchange where possible
    Next batch is 45% complete
]]
local function lines(text) local out={}; for line in text:gmatch("[^\r\n]+") do out[#out+1]=line end; return out end
local function equal(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function code(err,want) equal(type(err)=="table" and err.code,want) end
local mock, context, observer, adapter
local function reset(rank)
    API:_reload(); mock=Mock.new(); observer=nil
    mock.gmcp={char={vitals={name="TestOwner",rank=rank or "Manufacturer"},
        company={name="Sample Ltd",ceo="TestOwner",cash=7000000,depots={"Example World"},factories={{number=1,output="Firewalls",planet="Example World"}}}}}
    if rank=="Industrialist" then mock.gmcp.char.business=mock.gmcp.char.company; mock.gmcp.char.company=nil end
    adapter={name="company-test"}
    for _,name in ipairs({"f2ceVersion","registerEvent","unregisterEvent","timer","cancelTimer",
        "sendCommand","gmcpSnapshot","nativeCommandBlocker","haulingStatus","navState"}) do
        adapter[name]=function(...) return mock[name](mock,...) end
    end
    adapter.observeLine=function(callback) observer=callback; return 1 end
    adapter.unobserveLine=function() observer=nil end
    adapter.parseFactory=f2t_factory_parse_display
    adapter.parseDepot=f2t_depot_parse_display
    API._install(adapter)
    assert(API.modules.register({id="test.company",version="1.0.0",authorize=function() return true end}))
    context=assert(API.modules.enable("test.company"))
end
local passed,failed=0,0
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1; print("PASS "..name) else failed=failed+1; print("FAIL "..name..": "..tostring(err)) end
end
test("complete display preserves inputs and both kinds of profit",function()
    local value=assert(f2t_factory_parse_display(lines(fixture),1))
    equal(value.working_capital,-1000); equal(value.profit,-200); equal(value.current_net,36975)
    equal(value.inputs[1].commodity,"Semiconductors"); equal(value.inputs[1].shortfall,15)
    equal(value.inputs_met,false); equal(value.stored,750)
end)
test("wrapped display and input-free factory",function()
    local text=fixture:gsub("Inputs:\n    Semiconductors   Required: 20   Available: 5","Inputs:\n    None")
        :gsub("Next batch is 45%% complete","Next batch is 45%%\ncomplete")
    local value=assert(f2t_factory_parse_display(lines(text),1))
    equal(#value.inputs,0); equal(value.inputs_met,true)
end)
test("malformed partial duplicate and wrong-slot displays fail closed",function()
    equal(f2t_factory_parse_display(lines(fixture),2),nil)
    for _,text in ipairs({fixture:gsub("Next batch is 45%% complete",""),
        fixture:gsub("Available: 5","Available: 5 Semiconductors Required: 20 Available: 5"),
        fixture:gsub("40,000ig","4,00ig"),fixture:gsub("750 tons of Firewalls","749 tons of Firewalls"),
        (fixture:gsub("Finance:","Warning: incomplete Finance:"))}) do
        equal(f2t_factory_parse_display(lines(text),1),nil)
    end
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." refresh waits for an actual GMCP push",function()
    reset(rank); local calls=0
    assert(API.company.refresh(context,function(value,err) assert(value,tostring(err)); equal(err,nil); calls=calls+1 end))
    equal(mock.sent[1].command,rank=="Industrialist" and "di business" or "di company")
    local channel=rank=="Industrialist" and "business" or "company"
    assert(API.commands._lease); API.data.refresh(channel); equal(calls,0)
    mock:fireEvent("gmcp.char."..(channel=="business" and "company" or "business")); equal(calls,0)
    mock:fireEvent("gmcp.char."..channel); equal(calls,1); equal(API.commands._lease,nil)
    local copy=API.company.snapshot(); copy.cash=0; equal(API.company.snapshot().cash,7000000)
end)
end
test("complete factory response releases broker before callback",function()
    reset(); local calls=0
    assert(API.company.inspect(context,1,function(value,err)
        assert(value,tostring(err)); equal(err,nil); equal(API.commands._lease,nil); equal(observer,nil); calls=calls+1
    end))
    equal(mock.sent[1].command,"display factory 1")
    for _,line in ipairs(lines(fixture)) do observer(line) end
    equal(calls,1)
end)
test("partial display timeout cleans observer and ignores late lines",function()
    reset(); local calls=0
    assert(API.company.inspect(context,1,function(value,err) equal(value,nil); code(err,"E_COMPANY_TIMEOUT"); calls=calls+1 end))
    local late=observer; late("Sample Ltd: Firewalls Production Facility #1")
    mock:runTimers(); equal(calls,1); equal(observer,nil); equal(API.commands._lease,nil)
    late(fixture); equal(calls,1)
end)
test("wrong company identity and rank are rejected without sends",function()
    reset("Trader"); local value,err=API.company.refresh(context,function() end)
    equal(value,nil); code(err,"E_COMPANY_RANK"); equal(#mock.sent,0)
    reset(); mock.gmcp.char.company.ceo="SomeoneElse"; mock:fireEvent("gmcp.char.company")
    value,err=API.company.inspect(context,1,function() end)
    equal(value,nil); code(err,"E_COMPANY_DATA"); equal(#mock.sent,0)
end)
test("company switch during capture rejects even a complete old display",function()
    reset(); local calls=0
    assert(API.company.inspect(context,1,function(value,err) equal(value,nil); code(err,"E_COMPANY_IDENTITY"); calls=calls+1 end))
    mock.gmcp.char.vitals.name="SomeoneElse"; mock:fireEvent("gmcp.char.vitals")
    observer(fixture); equal(calls,1); equal(API.commands._lease,nil)
end)
test("cancel and disconnect never complete a stale request",function()
    for _,disconnect in ipairs({false,true}) do
        reset(); local calls=0
        local handle=assert(API.company.inspect(context,1,function() calls=calls+1 end))
        local late=observer
        if disconnect then API._reconnectReset("disconnect") else handle:cancel() end
        equal(observer,nil); equal(API.commands._lease,nil); late(fixture); mock:runTimers(); equal(calls,0)
    end
end)
test("contention unknown slot and injection cannot send a request",function()
    reset()
    for _,number in ipairs({0,16,"1;buy factory",2}) do
        equal(API.company.inspect(context,number,function() end),nil)
    end
    mock.native_blocker={kind="hauling"}
    local value,err=API.company.refresh(context,function() end)
    equal(value,nil); code(err,"E_COMMAND_CONTENTION"); equal(#mock.sent,0)
end)
test("missing factory server reply is an error not an empty valid factory",function()
    reset(); local calls=0
    assert(API.company.inspect(context,1,function(value,err) equal(value,nil); code(err,"E_FACTORY_MISSING"); calls=calls+1 end))
    observer("You don't have a factory with that number!"); equal(calls,1); equal(API.commands._lease,nil)
end)
local depot=[[Location: Example World
 Capacity: 20 cargo bays Workforce: 10 Efficiency: 100%
 Bay # 1 Semiconductors Cost 300ig/ton (Origin Other World, Other System system)
 Bay # 3 Firewalls Cost 1,200ig/ton (Origin Example World, Example System system)
]]
local function fence(rank,summary)
    if rank=="Industrialist" then observer("Sample Ltd registered business - CEO Industrialist TestOwner")
    else
        observer("Company Report for Sample Ltd:")
        observer("Example World - Capacity: 20 bays ("..(summary or 2).." in use) 100% efficiency")
    end
end
test("strict depot parsing handles empty, wrapped, gapped full bays",function()
    local d=assert(f2t_depot_parse_display(lines(depot),"Example World"))
    equal(d.used_bays,2); equal(d.free_bays,18); equal(d.inventory.semiconductors,75); equal(d.bays[2].cost_per_ton,1200)
    equal(assert(f2t_depot_parse_display(lines(depot:gsub("Example System","Example\nSystem")),"Example World")).used_bays,2)
    d=assert(f2t_depot_parse_display({"Location: Example World Capacity: 20 cargo bays Workforce: 10 Efficiency: 100% The depot is empty."},"Example World"))
    equal(d.used_bays,0); equal(d.free_bays,20)
    for _,bad in ipairs({depot:gsub("# 3","# 1"),depot:gsub("# 3","# 21"),depot:gsub("1,200ig","1,20ig"),
        depot:gsub("1,200ig",",120ig"),depot:gsub("Other System system%)","Other System"),depot.."Unexpected text"}) do
        equal(f2t_depot_parse_display(lines(bad),"Example World"),nil)
    end
    equal(f2t_depot_parse_display(lines(depot),"Other World"),nil)
end)
for _,rank in ipairs({"Industrialist","Manufacturer"}) do
test(rank.." depot requires ordered owner fence and real rank-specific GMCP",function()
    reset(rank); local calls=0
    assert(API.company.depot(context,"Example World",function(d,err)
        assert(d,tostring(err)); equal(d.owner,"Sample Ltd"); equal(d.used_bays,2); equal(API.commands._lease,nil); calls=calls+1
    end))
    equal(mock.sent[1].command,"display depot Example World")
    equal(mock.sent[2].command,rank=="Industrialist" and "di business" or "di company")
    observer(depot); equal(calls,0); fence(rank); equal(calls,0)
    local channel=rank=="Industrialist" and "business" or "company"
    API.data.refresh(channel); equal(calls,0)
    mock:fireEvent("gmcp.char."..channel); equal(calls,1); equal(observer,nil)
end)
end
test("early GMCP waits for text fence and manufacturer occupancy",function()
    reset(); local calls=0
    assert(API.company.depot(context,"Example World",function(d,err) assert(d,tostring(err)); calls=calls+1 end))
    mock:fireEvent("gmcp.char.company"); equal(calls,0)
    observer(depot); observer("Company Report for Sample Ltd:"); equal(calls,0)
    observer("Example World - Capacity: 20 bays (2 in use) 100% efficiency"); equal(calls,1)
end)
test("depot changed, ownership switch and truncated capture reject",function()
    reset(); local err
    assert(API.company.depot(context,"Example World",function(_,e) err=e end)); observer(depot); fence(nil,3)
    mock:fireEvent("gmcp.char.company"); code(err,"E_DEPOT_CHANGED")
    reset(); err=nil
    assert(API.company.depot(context,"Example World",function(_,e) err=e end)); observer(depot)
    mock.gmcp.char.company.ceo="Other"; mock:fireEvent("gmcp.char.company"); code(err,"E_COMPANY_IDENTITY")
    reset(); err=nil
    assert(API.company.depot(context,"Example World",function(_,e) err=e end)); observer(depot)
    mock:runTimers(); code(err,"E_COMPANY_TIMEOUT"); equal(observer,nil); equal(API.commands._lease,nil)
end)
test("depot missing, unsafe name and contention send nothing",function()
    reset()
    for _,planet in ipairs({"Missing","Example World;quit","Example World\nquit"}) do equal(API.company.depot(context,planet,function() end),nil) end
    equal(#mock.sent,0)
    mock.native_blocker={kind="hauling"}; equal(API.company.depot(context,"Example World",function() end),nil); equal(#mock.sent,0)
end)
test("depot disconnect and OFF reject late response without callback",function()
    for _,disconnect in ipairs({true,false}) do
        reset(); local calls=0
        local h=assert(API.company.depot(context,"Example World",function() calls=calls+1 end)); local late=observer
        if disconnect then API._reconnectReset("disconnect") else h:cancel("OFF") end
        late(depot); mock:runTimers(); equal(calls,0); equal(API.commands._lease,nil); equal(observer,nil)
    end
end)
test("Industrialist never uses a stale company snapshot",function()
    reset("Industrialist"); mock.gmcp.char.business=nil; mock.gmcp.char.company={name="Old Ltd",ceo="TestOwner",factories={}}
    mock:fireEvent("gmcp.char.company"); mock:fireEvent("gmcp.char.business")
    equal(API.company.snapshot(),nil)
end)
print(string.format("RESULT %d passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end
