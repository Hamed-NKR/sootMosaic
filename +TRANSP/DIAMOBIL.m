function dm = DIAMOBIL(dg, da, fl, slip)
% "DIAMOBIL" calculates the mobility diameter by interpolation between...
%   ...free molecular and continuum limit approximations.
% ----------------------------------------------------------------------- %
% 
% Inputs:
%     dg: Aggregates' gyration diameter
%     da: ~ projected area equivalent diameter
%     fl: fluid flow characteristics structure
%     slip: Slip correction model of TRANSP.CUNNINGHAM, default...
%         ...'per_caller_7658971' (the constants of 'kim2005', solved with...
%         ...the default tolerance of fzero)
% ----------------------------------------------------------------------- %
% 
% Outputs:
%     dm: Mobility diameter
% ----------------------------------------------------------------------- %

if ~exist('slip', 'var') || isempty(slip)
    slip = 'per_caller_7658971'; % constants of each caller at 7658971
end

% Cunningham correction factor (x: particle diameter in m)
cc = @(x) TRANSP.CUNNINGHAM(x, fl.lambda, slip, 'DIAMOBIL');

dm_c = 0.75 * dg; % continuum regime asymptotic approximation initialized

% dm_c = zeros(length(dg),1);
% dm_c(npp < 100) = dpp(npp < 100) .* npp(npp < 100).^0.46;
% dm_c(npp >= 100) = 0.65 * dpp(npp >= 100) .* npp(npp >= 100).^0.56;

R_adj = da.^2 ./ (2 * dm_c);

f_not = (fl.mu * 3 * pi * dm_c) ./ cc(2 * R_adj); % Kn = lambda / R_adj

dm0 = 0.75 * dg; % initial guess

dm = zeros(length(dm0),1);

% The per_caller_7658971 model keeps the default tolerance of fzero...
    % ...(TolX = eps, an absolute 2.2e-16 m, about 1e-9 of a 100 nm...
    % ...diameter). The other models set TolX to eps times the initial...
    % ...guess, an absolute tolerance scaled by the diameter, so the...
    % ...friction of dm equals the adjusted sphere friction to round-off.
legacy = strcmp(slip, 'per_caller_7658971');
opts_fz = optimset('TolX', eps);
% dm2 = zeros(length(dm0),1);

% figure(1)

for i = 1 : length(dm0)
%     f = @(x) 3 * pi * fl.mu * x ./ cc(x);
    df = @(x) 3 * pi * fl.mu * x ./ cc(x) - f_not(i);
    
    if legacy
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

