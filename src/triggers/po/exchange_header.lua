-- po_exchange_header — patterns declared in triggers.json
if f2t_po.phase == "capturing_exchange" then
    f2t_po.header_planet = tostring(line):match("^%s*(.-)%s+exchange %- all products:")
    deleteLine()
    f2t_po_capture_reset_timer()
    f2t_debug_log("[po] Exchange header detected")
end
