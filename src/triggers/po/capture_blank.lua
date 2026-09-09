-- Suppress only blanks inside an identified active PO response. Never leave
-- a global capture/gag trigger enabled during navigation or normal gameplay.
if f2t_po and f2t_po.phase ~= "idle" and f2t_po.header_planet then
    deleteLine()
elseif F2T_PO_BLANK_TAIL and F2T_PO_BLANK_TAIL.remaining > 0 then
    F2T_PO_BLANK_TAIL.remaining = F2T_PO_BLANK_TAIL.remaining - 1
    deleteLine()
end
