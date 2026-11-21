function SAVE_PUBLIC_MAT(target, flags, varargin)
% "SAVE_PUBLIC_MAT" saves caller variables with local paths reduced.
% The named variables, or the whole caller workspace when no name is...
%     ...given, are copied into one structure, reduced by UTILS.PUBLIC_COPY...
%     ...and saved with -struct under their own names. The caller...
%     ...variables are unchanged.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     target: MAT file to write
%     flags: Cell of save options, such as {'-v7.3'}, or {} for the...
%         ...default format
%     varargin: Variable names in the caller workspace
% ----------------------------------------------------------------------- %

names = varargin;
if isempty(names)
    names = evalin('caller', 'who');
end
payload = struct();
for k = 1:numel(names)
    payload.(names{k}) = evalin('caller', names{k});
end
payload = UTILS.PUBLIC_COPY(payload);
save(target, '-struct', 'payload', flags{:});
end
