function [data, source, provenance] = LOAD_VALIDATION_SOURCE(source_cfg, opts)
% "LOAD_VALIDATION_SOURCE" loads the configured data source.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     source_cfg: Inline source fields or source_id with field overrides
%     opts: Optional registry and download inputs for LOAD_DATASET_SOURCE
% ----------------------------------------------------------------------- %
%
% Outputs:
%     data: Requested data
%     source: Resolved source metadata
%     provenance: Registry configuration digests and inline overrides
% ----------------------------------------------------------------------- %

if nargin < 1, source_cfg = []; end
if nargin < 2, opts = struct(); end
opts.Caller = 'LOAD_VALIDATION_SOURCE';
opts.ReuseCache = true;
opts.ReturnStruct = true;
opts.ResolvePaths = false;
opts.CanonicalPaths = false;
opts.DefaultCacheDir = '';
[data, source, provenance] = UTILS.LOAD_DATASET_SOURCE(source_cfg, opts);
end
