function CHECK_SAVED_DM(dm_saved, dm_now)
% "CHECK_SAVED_DM" stops when the mobility diameters stored with a saved...
%   ...population differ from the mobility diameters of that population.
% ----------------------------------------------------------------------- %
%
%   Inputs
%   - dm_saved, mobility diameters written to the saved data (m)
%   - dm_now, mobility diameters of the population at save time (m)
%
%   Entries that are undefined in both inputs count as equal. A size or...
%   ...value difference stops with the identifier...
%   ...sootMosaic:LD2:SavedDmMismatch.
% ----------------------------------------------------------------------- %

if ~isequaln(dm_saved, dm_now)
    error('sootMosaic:LD2:SavedDmMismatch', ...
        'Saved mobility diameters differ from the population at save time.')
end

end
