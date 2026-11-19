function [parsdata, r_n_agg] = TRIM_LD2_OUTPUT(parsdata, r_n_agg, ind_dat)
% "TRIM_LD2_OUTPUT" retains stored snapshots and their number fractions.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     parsdata: Preallocated snapshot structure array
%     r_n_agg: Requested number fractions
%     ind_dat: Index of the next snapshot to store
% ----------------------------------------------------------------------- %
%
% Outputs:
%     parsdata: Stored snapshot prefix
%     r_n_agg: Corresponding number fractions
% ----------------------------------------------------------------------- %

parsdata(ind_dat:end) = [];
r_n_agg = r_n_agg(1:numel(parsdata));
end
