-- Suppress only blanks inside an identified active PO response. Never leave
-- a global capture/gag trigger enabled during navigation or normal gameplay.
if f2t_po and f2t_po.phase ~= "idle" and f2t_po.header_planet then deleteLine() end
