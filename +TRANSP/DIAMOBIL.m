function dm = DIAMOBIL(dg, da, fl, slip, opts)
% "DIAMOBIL" calculates the mobility diameter by interpolation between...
%   ...free molecular and continuum limit approximations.
% ----------------------------------------------------------------------- %
% 
% Inputs:
%     dg: Aggregates' gyration diameter (row or column)
%     da: ~ projected area equivalent diameter (same number of entries)
%     fl: fluid flow characteristics structure
%     slip: Slip correction model of TRANSP.CUNNINGHAM, default...
%         ...'per_caller_7658971' (the constants of 'kim2005', solved with...
%         ...the default tolerance of fzero)
%     opts: Interpolation options structure (optional)
%         continuum: Continuum regime diameter, 'fixed_075dg' (0.75 dg,...
%             ...the default) or 'sorensen_backbone' (TRANSP.CONTINUUM_DM...
%             ...'backbone', with dm = dp for single primaries)
%         root: Root solve, 'start_point_7658971' (fzero from one start...
%             ...point, the default) or 'bracketed' (fzero on the bracket...
%             ...between the continuum diameter and da)
%         npp: Number of primaries, needed by 'sorensen_backbone'
%         dpp1: Primary diameter of single-primary aggregates, needed by...
%             ...'sorensen_backbone'
% ----------------------------------------------------------------------- %
% 
% Outputs:
%     dm: Mobility diameter (column vector, one entry per aggregate)
% ----------------------------------------------------------------------- %
%
% Method. dm solves the adjusted sphere interpolation of Rogak et al....
%     ...(1993, p. 28, Eqs. 10 to 12, reference 9 of the README),...
%     ...dm / Cc(2 lambda / dm) = dm_c / Cc(Kn_adj) with Kn_adj = 2 lambda...
%     ...dm_c / da^2 = lambda / R_adj, where dm_c is the continuum regime...
%     ...diameter and the free molecular diameter is da (dA = dm in the...
%     ...free molecular regime, pp. 27 and 28). Rows and columns are...
%     ...accepted for dg, da, opts.npp and opts.dpp1, each is read as...
%     ...one value per aggregate in the same order.
% ----------------------------------------------------------------------- %

if numel(da) ~= numel(dg)
    error('sootMosaic:DIAMOBIL:SizeMismatch', ['dg and da must hold ', ...
        'one value per aggregate each.'])
end
dg = dg(:); % one orientation for every per-aggregate input
da = da(:);
if ~exist('slip', 'var') || isempty(slip)
    slip = 'per_caller_7658971'; % constants of each caller at 7658971
end
if ~exist('opts', 'var') || isempty(opts)
    opts = struct();
end
if (~isfield(opts, 'continuum')) || isempty(opts.continuum)
    opts.continuum = 'fixed_075dg'; % 0.75 dg at every N
end
if (~isfield(opts, 'root')) || isempty(opts.root)
    opts.root = 'start_point_7658971'; % fzero from one start point
end
if ~any(strcmp(opts.root, {'start_point_7658971', 'bracketed'}))
    error('sootMosaic:DIAMOBIL:UnknownRootSolve', ['Unknown root solve ', ...
        '%s. Known names are start_point_7658971 and bracketed.'], opts.root)
end

% Cunningham correction factor (x: particle diameter in m)
cc = @(x) TRANSP.CUNNINGHAM(x, fl.lambda, slip, 'DIAMOBIL');

% Continuum regime asymptotic approximation
switch opts.continuum
    case 'fixed_075dg'
        dm_c = 0.75 * dg; % continuum regime asymptotic approximation
        dm0 = 0.75 * dg; % initial guess
        is_1 = false(size(dg)); % no separate single-primary branch
    case 'sorensen_backbone'
        if ~isfield(opts, 'npp') || ~isfield(opts, 'dpp1') || ...
                numel(opts.npp) ~= numel(dg) || numel(opts.dpp1) ~= numel(dg)
            error('sootMosaic:DIAMOBIL:MissingPrimaryData', ['The ', ...
                'sorensen_backbone continuum diameter needs opts.npp and ', ...
                'opts.dpp1 for every aggregate.'])
        end
        dm_c = TRANSP.CONTINUUM_DM(opts.npp(:), dg, opts.dpp1(:), ...
            'backbone');
        dm0 = dm_c;
        is_1 = (opts.npp(:) == 1); % a single sphere has dm = dp at every Kn
    otherwise
        error('sootMosaic:DIAMOBIL:UnknownContinuumDiameter', ['Unknown ', ...
            'continuum diameter %s. Known names are fixed_075dg and ', ...
            'sorensen_backbone.'], opts.continuum)
end

R_adj = da.^2 ./ (2 * dm_c);

f_not = (fl.mu * 3 * pi * dm_c) ./ cc(2 * R_adj); % Kn = lambda / R_adj

dm = zeros(length(dm0),1);

% The per_caller_7658971 model keeps the default tolerance of fzero...
    % ...(TolX = eps, an absolute 2.2e-16 m, about 1e-9 of a 100 nm...
    % ...diameter). The other models set TolX to eps times the initial...
    % ...guess, an absolute tolerance scaled by the diameter, so the...
    % ...friction of dm equals the adjusted sphere friction to round-off.
legacy = strcmp(slip, 'per_caller_7658971');
bracketed = strcmp(opts.root, 'bracketed');
opts_fz = optimset('TolX', eps);
% dm2 = zeros(length(dm0),1);

% figure(1)

for i = 1 : length(dm0)
%     f = @(x) 3 * pi * fl.mu * x ./ cc(x);
    df = @(x) 3 * pi * fl.mu * x ./ cc(x) - f_not(i);
    
    if is_1(i)
        dm(i) = dm_c(i); % the primary diameter, exact for a sphere
    elseif bracketed
        dm(i) = bracketed_root(df, dm_c(i), da(i), f_not(i));
    elseif legacy
        dm(i) = fzero(df,(dm0(i) + da(i)) / 2);
    else
        opts_fz.TolX = eps * (dm0(i) + da(i)) / 2;
        dm(i) = fzero(df, (dm0(i) + da(i)) / 2, opts_fz);
    end
%     dm(i) = lsqnonlin(df,(dm0(i) + da(i)) / 2);
    
%     dm_fit = [0.1 * min(dm_c(i),da(i)), 10 * max(dm_c(i),da(i))];
%     dm_fit = logspace(log10(dm_fit(1)), log10(dm_fit(2)), 1e4);
%     
%     f_fit = f(dm_fit);
%     df_fit = df(dm_fit);
%     dm2(i) = dm_fit(abs(df_fit) == min(abs(df_fit)));
%     
%     plot(dm_fit, f_fit)
%     hold on
%     plot(dm_fit, repmat(f_not(i), 1e4, 1))
%     hold off
%     legend('f_{d_m}','f_{d_{adj}}')
%     
%     set(gca, 'XScale', 'log', 'YScale', 'log')
%     axis([-inf inf -inf inf])
end

end

function x = bracketed_root(df, dm_c, da, f_not)
% "bracketed_root" solves df(x) = 0 between dm_c and da. The adjusted...
    % ...sphere friction lies between the friction of a sphere of...
    % ...diameter dm_c and of diameter da, since Cc(Kn) / Kn falls with Kn...
    % ...for the slip corrections of TRANSP.CUNNINGHAM, so the root lies...
    % ...in [min(dm_c, da), max(dm_c, da)]. The tolerance is that of the...
    % ...other models (eps times the midpoint).
lo = min(dm_c, da);
hi = max(dm_c, da);
if lo == hi
    x = lo;
    return
end
g_lo = df(lo);
g_hi = df(hi);
if g_lo == 0
    x = lo;
elseif g_hi == 0
    x = hi;
elseif sign(g_lo) ~= sign(g_hi)
    x = fzero(df, [lo, hi], optimset('TolX', eps * (lo + hi) / 2));
elseif min(abs(g_lo), abs(g_hi)) <= 64 * eps * f_not
    % Both ends on one side by round-off only, the root is at the end...
        % ...with the smaller residual
    if abs(g_lo) <= abs(g_hi)
        x = lo;
    else
        x = hi;
    end
else
    error('sootMosaic:DIAMOBIL:NoBracket', ['The adjusted sphere ', ...
        'friction is not bracketed by the frictions at dm_c = %.6g m and ', ...
        'da = %.6g m.'], dm_c, da)
end
end
