-- Synthetic fixture matching Factory::Display's complete protocol; no profile data.
local Mock=dofile("tests/api/mock_adapter.lua")
dofile("src/scripts/api/v1.lua")
dofile("src/scripts/api/services.lua")
dofile("src/scripts/api/company.lua")
dofile("src/scripts/factory/display_parser.lua")
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
        company={name="Sample Ltd",ceo="TestOwner",cash=7000000,factories={{number=1,output="Firewalls",planet="Example World"}}}}}
    adapter={name="company-test"}
    for _,name in ipairs({"f2ceVersion","registerEvent","unregisterEvent","timer","cancelTimer",
        "sendCommand","gmcpSnapshot","nativeCommandBlocker","haulingStatus","navState"}) do
        adapter[name]=function(...) return mock[name](mock,...) end
    end
    adapter.observeLine=function(callback) observer=callback; return 1 end
    adapter.unobserveLine=function() observer=nil end
    adapter.parseFactory=f2t_factory_parse_display
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
    assert(API.commands._lease); API.data.refresh("company"); equal(calls,0)
    mock:fireEvent("gmcp.char.company"); equal(calls,1); equal(API.commands._lease,nil)
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
print(string.format("RESULT %d passed, %d failed",passed,failed))
if failed>0 then os.exit(1) end
