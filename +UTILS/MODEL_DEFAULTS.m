function profile = MODEL_DEFAULTS(name)
% "MODEL_DEFAULTS" returns the complete built-in profile mirror.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     name: Shipped profile name
% ----------------------------------------------------------------------- %
%
% Outputs:
%     profile: Common and stage sections, or empty for an unknown name
% ----------------------------------------------------------------------- %

profile = [];
if ~any(strcmp(name, {'current', 'article1_7658971'})), return; end
profile = struct();
profile.config_version = 1;
profile.profile = 'current';
profile.description = 'Present default choices';
profile.constants.rho_bc_kg_m3 = 1.86e3;
profile.constants.m_air_kg_mol = 28.97e-3;
profile.constants.kb_j_k = 1.381e-23;
profile.constants.na_mol_inv = 6.022e23;
profile.constants.ru_j_mol_k = 8.314;
profile.constants.rho_aero_ref_kg_m3 = 1000;
profile.gas.model = 'sutherland';
profile.gas.sutherland.mu_ref_pa_s = 1.716e-5;
profile.gas.sutherland.t_ref_k = 273.15;
profile.gas.sutherland.s_k = 110.4;
profile.gas.mean_free_path.lambda_ref_m = 67.3e-9;
profile.gas.mean_free_path.t_ref_k = 296.15;
profile.gas.mean_free_path.s_k = 110.4;
profile.gas.mean_free_path.p_ref_pa = 101325;
profile.gas.presets.room.mu_pa_s = 1.813e-5;
profile.gas.presets.room.lambda_m = 6.8e-8;
profile.gas.presets.room.t_k = 293.15;
profile.gas.presets.flame.mu_pa_s = 5.647e-5;
profile.gas.presets.flame.lambda_m = 4.98e-7;
profile.gas.presets.flame.t_k = 1700;
profile.gas.preset_warning.temperature_tol_k = 1;
profile.gas.preset_warning.pressure_rel_tol = 0.01;
profile.gas.preset_warning.p_ref_pa = 101325;
profile.slip.model = 'kim2005';
profile.slip.kim2005.a = 1.165;
profile.slip.kim2005.b = 0.483;
profile.slip.kim2005.c = 0.997;
profile.slip.per_caller_7658971.mobil = [1.254; 0.4; 1.1];
profile.slip.per_caller_7658971.diamobil = [1.165; 0.483; 0.997];
profile.slip.per_caller_7658971.aerodyn = [1.165; 0.483; 0.997];
profile.slip.per_caller_7658971.tabgen = [1.257; 0.4; 0.55];
profile.mobility.method = 'interp';
profile.mobility.continuum_diameter = 'sorensen_backbone';
profile.mobility.root_solve = 'bracketed';
profile.mobility.eq17.prefactor = 1.29;
profile.mobility.eq17.exponent = -0.13;
profile.mobility.dm_c_factor = 0.75;
profile.mobility.backbone_crossover_n = 74;
profile.mobility.doublet_exponent = 0.46;
profile.mobility.doublet_divisor = 1.6;
profile.projection.method = 'isotropic';
profile.projection.cache = true;
profile.projection.points = 1024;
profile.projection.orientations = 64;
profile.projection.replicates = 4;
profile.projection.tol = 0.01;
profile.projection.cache_tol = 1e-9;
profile.step.step_frac = 0.5;
profile.step.step_policy = 'warn';
profile.initial_velocity.sampler = 'maxwell_boltzmann';
profile.diagnostics.knudsen = true;
profile.numerics.mobil_step_root_tol = 1e-12;
profile.numerics.mobil_series_switch = 1e-2;
profile.numerics.march_series_switch = 2;
profile.numerics.march_series_terms = 10;
profile.numerics.connect_margin = 1e-13;
profile.numerics.projection_default_n = 1e4;
profile.numerics.projection_min_n = 1e2;
profile.reference.d_tem = 0.35;
profile.reference.dpp100_nm = 17.8;
profile.reference.mass_mobility_exponent = 2.48;
profile.reference.rho100_kg_m3 = 510;
profile.reference.m100_fg = 0.267;
profile.stages.LD1 = struct();
profile.stages.LD2 = struct();
profile.stages.INV.constants = struct();
profile.stages.INV.gas = struct();
profile.stages.INV.slip = struct();

if strcmp(name, 'article1_7658971')
    profile.profile = 'article1_7658971';
    profile.description = 'Fixed first article choices';
    profile.gas.model = 'flame';
    profile.slip.model = 'per_caller_7658971';
    profile.mobility.method = 'sorensen_eq17';
    profile.mobility.continuum_diameter = 'fixed_075dg';
    profile.mobility.root_solve = 'start_point_7658971';
    profile.projection.method = 'euler_7658971';
    profile.projection.cache = false;
    profile.projection.points = 100;
    profile.projection.orientations = 5;
    profile.projection.replicates = 1;
    profile.projection.tol = Inf;
    profile.initial_velocity.sampler = 'mean_speed_7658971';
    profile.diagnostics.knudsen = false;
    profile.stages = struct();
    profile.stages.LD1.gas.model = 'flame';
    profile.stages.LD1.mobility.method = 'sorensen_eq17';
    profile.stages.LD2.gas.model = 'room';
    profile.stages.LD2.mobility.method = 'interp';
end
end
