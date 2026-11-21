function cfg = LD1_CONFIG_EXPLICIT_CHOICES(cfg)
% "LD1_CONFIG_EXPLICIT_CHOICES" supplies explicit task choices for QA.
% ----------------------------------------------------------------------- %
%
% Inputs/Outputs:
%     cfg: LD1 task fixture with explicit choices over its profile
% ----------------------------------------------------------------------- %

cfg.transport.fluid_options.amb = 'sutherland';
cfg.transport.mobility_options.mtd = 'interp';
cfg.transport.mobility_options.step_frac = 0.5;
cfg.transport.mobility_options.step_policy = 'warn';
cfg.transport.mobility_options.slip = 'kim2005';
cfg.transport.mobility_options.continuum_diameter = 'sorensen_backbone';
cfg.transport.mobility_options.root_solve = 'bracketed';
cfg.transport.mobility_options.projection = 'isotropic';
cfg.transport.mobility_options.proj_cache = true;
cfg.transport.mobility_options.proj_points = 1024;
cfg.transport.mobility_options.proj_orientations = 64;
cfg.transport.mobility_options.proj_replicates = 4;
cfg.transport.mobility_options.proj_tol = 0.01;
cfg.transport.diagnostics_options.knudsen = true;
cfg.transport.velocity_options.sampler = 'maxwell_boltzmann';
end
