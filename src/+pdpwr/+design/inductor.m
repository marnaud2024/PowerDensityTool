function proj = inductor(D, core, opts)
%INDUCTOR Iterative inductor design (Magnetics or Magmattec toroidal cores).
%
%   proj = pdpwr.design.inductor(D, core)
%   proj = pdpwr.design.inductor(D, core, opts)
%
%   D - design data struct (see GerarIndutores callback for the full list):
%       .Vd          DC bus voltage [V]
%       .ILmed       Average inductor current [A]
%       .DeltaIL     Peak-to-peak ripple [A]
%       .ILef        RMS current [A] (computed by caller)
%       .L           Required inductance [H] (computed from Vd, fs, DeltaIL)
%       .IL_max      Maximum allowed ripple in same units as DeltaIL [A]
%       .J           Current density [A/cm^2]
%       .fs          Effective switching frequency for core loss [Hz]
%       .r_awg       Wire resistance [ohm/m]
%       .Aawg        Wire cross section [cm^2]
%       .Dextawg     Wire external diameter [cm]
%       .temp_ambiente Ambient temperature [degC]
%       .DeltaTmax   Maximum allowed temperature rise [degC]
%       .kumin .kumax Window utilization bounds
%       .MaxLoss .MaxVol Hard caps for losses and volume
%
%   core - core data struct:
%       .id              Core ID label (passed through)
%       .mi_rel          Initial relative permeability
%       .le_mm           Magnetic path length [mm]
%       .Ae_mm2          Cross-section [mm^2]
%       .Vol_mm3         Core volume [mm^3]
%       .OD_mm, .ID_mm   Outer/inner diameter [mm]
%       .HT_mm           Stack height [mm]
%       .stacks          Number of stacked cores
%   For Magnetics cores additionally:
%       .mi_a .mi_b .mi_c       Roll-off polynomial 1/(a + b*H^c)
%       .P_a .P_b .P_c          Steinmetz core-loss polynomial in mW/cm^3
%   For Magmattec cores:
%       .AL0_nHesp2             Catalog AL value [nH/esp^2]
%       .pcore_fn               function handle for core loss [@(fs_kHz, Bpk_G) -> mW/cm^3]
%
%   opts - optional struct:
%       .legacyBpkBug (default false)
%             If true, reproduce the legacy bug where B = mu0*mu_r*I/(CEM/1000)
%             instead of mu0*mu_r*N*I/le. Used by regression tests.
%
%   Returns proj struct with .N (NaN if rejected) and detailed result fields.

    if nargin < 3, opts = struct(); end
    if ~isfield(opts, 'legacyBpkBug'), opts.legacyBpkBug = false; end

    mu0 = 4 * pi * 1e-7;
    Aw_mm2 = (core.ID_mm / 2)^2 * pi;                 % window area [mm^2]
    AL0    = core.mi_rel * mu0 * (core.Ae_mm2 / core.le_mm) * 1e-3;  % [H/esp^2]
    AL     = AL0;

    % Iterate to find N consistent with permeability roll-off
    miRollOff = 100;
    if isfield(core, 'AL0_nHesp2') && ~isempty(core.AL0_nHesp2)
        AL0 = core.AL0_nHesp2 * 1e-9;                 % Magmattec direct AL
        AL  = AL0;
    end
    N = 1;
    for it = 1:25
        N1 = ceil(sqrt(D.L / AL));
        Hmed = 4 * pi * (N1 / core.le_mm) * D.ILmed;  % H field, Oersted (le in mm, I in A)
        miRollOff = i_rollOff(core, Hmed);
        if miRollOff < 30
            % Permeability has collapsed (deep saturation) - this core cannot
            % realise the target inductance. Reject immediately instead of
            % iterating 25x toward a divide-by-zero (AL -> 0, N -> Inf).
            proj = i_reject('mu_rolloff<30'); return
        end
        AL = AL0 * miRollOff / 100;
        N  = ceil(sqrt(D.L / AL));
        if N == N1, break; end
    end

    if miRollOff < 30
        proj = i_reject('mu_rolloff<30'); return
    end

    % Wire window check
    Acu_cm2 = D.ILef / D.J;
    Nparal  = ceil(Acu_cm2 / D.Aawg);
    Aocup_cm2 = (D.Dextawg / 2)^2 * pi * N * Nparal;  % [cm^2]
    Ku = Aocup_cm2 / (Aw_mm2 * 0.01);                 % convert mm^2 -> cm^2
    if Ku > D.kumax, proj = i_reject('Ku>kumax'); return; end
    if Ku < D.kumin, proj = i_reject('Ku<kumin'); return; end

    % Mean turn length [mm]
    CEM_mm = (2 * core.HT_mm + (core.OD_mm - core.ID_mm)) * 1.1;

    % Peak flux density. We use the exact inductance identity B = L*I/(N*Ae),
    % which follows from L = N*Phi/I and Phi = B*Ae. This is equivalent to
    % B = mu0*mu_eff*N*I/le but cannot blow up (it uses the realised L and the
    % integer N directly, with no compounding of the permeability roll-off).
    % The legacy app used B = mu0*mu_r*I/(CEM/1000) - constant mu_r and the
    % mean-turn length CEM instead of the magnetic path le - reproduced when
    % opts.legacyBpkBug is true.
    le_m   = core.le_mm * 1e-3;
    Ae_m2  = core.Ae_mm2 * 1e-6;
    if opts.legacyBpkBug
        B_max = (mu0 * core.mi_rel * (D.ILmed + D.IL_max/2)) / (CEM_mm/1000);
        B_min = (mu0 * core.mi_rel * (D.ILmed - D.IL_max/2)) / (CEM_mm/1000);
    else
        B_max = D.L * (D.ILmed + D.IL_max/2) / (N * Ae_m2);
        B_min = D.L * (D.ILmed - D.IL_max/2) / (N * Ae_m2);
    end
    Bpk_T = 0.5 * (B_max + B_min);
    if ~isfinite(Bpk_T) || Bpk_T <= 0, proj = i_reject('Bpk_invalid'); return; end

    % Core loss
    if isfield(core, 'pcore_fn') && ~isempty(core.pcore_fn)
        % Magmattec: empirical pcore(fs_kHz, Bpk_G)
        Bpk_G = Bpk_T * 1e4;
        Pcore_mW_per_cm3 = core.pcore_fn(D.fs / 1000, Bpk_G);
        if isnan(Pcore_mW_per_cm3), proj = i_reject('pcore_out_of_range'); return; end
    else
        % Magnetics: Steinmetz polynomial P_a * B^P_b * f^P_c [mW/cm^3]
        Pcore_mW_per_cm3 = core.P_a * Bpk_T^core.P_b * (D.fs/1000)^core.P_c;
    end
    Pcore = (Pcore_mW_per_cm3 * 1e-3) * (core.Vol_mm3 * 1e-3);  % W

    % Copper loss with temperature feedback (converges in a few iterations)
    Tatual  = D.temp_ambiente;
    DeltaT  = Tatual - 20;
    for it = 1:6
        Rawg_ohm_m = D.r_awg * (1 + 0.00393 * DeltaT);
        Rfio_ohm   = N * CEM_mm * Rawg_ohm_m * 1e-3 / Nparal;
        Pcu        = Rfio_ohm * D.ILef^2;
        Ptotal     = Pcore + Pcu;
        Sa_mm2     = 2*pi*(core.OD_mm/2)^2 + 2*pi*core.OD_mm/4 * core.HT_mm;
        DeltaT     = (1e5 * Ptotal / Sa_mm2)^0.833;
    end
    if DeltaT > D.DeltaTmax, proj = i_reject('DeltaT>max'); return; end

    % Volume of wound inductor
    d_atual = 2 * core.ID_mm * (1 - sqrt(1 - Ku));
    Vol_cm3 = pi * ((core.OD_mm + d_atual) / 2)^2 * (core.HT_mm + d_atual) * 1e-3;

    % Final user-defined caps
    if isfield(D, 'MaxLoss') && Ptotal > D.MaxLoss, proj = i_reject('Ptotal>MaxLoss'); return; end
    if isfield(D, 'MaxVol')  && Vol_cm3 > D.MaxVol, proj = i_reject('Vol>MaxVol'); return; end

    proj = struct( ...
        'ID',       core.id, ...
        'mi',       core.mi_rel, ...
        'Ptotal',   Ptotal, ...
        'Pcore',    Pcore, ...
        'Pcu',      Pcu, ...
        'Vol',      Vol_cm3, ...
        'Ku',       Ku, ...
        'N',        N, ...
        'Nparal',   Nparal, ...
        'Compfio',  N * CEM_mm, ...
        'J',        D.J, ...
        'DeltaT',   DeltaT, ...
        'L',        D.L, ...
        'DeltaIL',  D.DeltaIL, ...
        'Stacks',   core.stacks, ...
        'fs',       D.fs, ...
        'Tfinal',   D.temp_ambiente + DeltaT, ...
        'Bpk',      Bpk_T, ...
        'RollOff',  miRollOff);
end


function mu = i_rollOff(core, H_Oe)
% Return percent permeability (0..100) as a function of H (Oersted).
% Both fits are only valid for moderate H; for large H they diverge
% (the Magmattec cubic shoots up because of its positive H^3 term), so we
% clamp the result to [0, 100] - a powder core never EXCEEDS its nominal
% permeability, it only rolls off below it.
    if isfield(core, 'mi_a') && ~isnan(core.mi_a)
        mu = 1 ./ (core.mi_a + core.mi_b * H_Oe^core.mi_c) * 100;
    else
        % Magmattec cubic fit from legacy app2 (ProjetoIndutormagmattec)
        mu = 2.6e-7 * H_Oe^3 - 1.9352e-4 * H_Oe^2 + 0.01696643 * H_Oe + 99.67957942;
    end
    mu = max(0, min(100, mu));
end


function p = i_reject(reason)
    if nargin < 1, reason = 'unknown'; end
    p = struct('ID', NaN, 'mi', NaN, 'Ptotal', NaN, 'Pcore', NaN, 'Pcu', NaN, ...
               'Vol', NaN, 'Ku', NaN, 'N', NaN, 'Nparal', NaN, 'Compfio', NaN, ...
               'J', NaN, 'DeltaT', NaN, 'L', NaN, 'DeltaIL', NaN, 'Stacks', NaN, ...
               'fs', NaN, 'Tfinal', NaN, 'Bpk', NaN, 'RollOff', NaN, 'reason', reason);
end
