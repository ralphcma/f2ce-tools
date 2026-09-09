-- Stop suppressing separators as soon as another real message appears.
if F2T_PO_BLANK_TAIL and tostring(line or "") ~= F2T_PO_BLANK_TAIL.summary then
    F2T_PO_BLANK_TAIL = nil
end
