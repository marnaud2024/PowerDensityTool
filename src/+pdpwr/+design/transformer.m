function proj = transformer(D, core, mat, opts)
%TRANSFORMER Single-design transformer evaluation (Magnetics / TDK / Magmattec cores).
%
%   proj = pdpwr.design.transformer(D, core, mat)
%   proj = pdpwr.design.transformer(D, core, mat, opts)
%
%   D    - design struct:
%        .Vd, .Vo, .n, .Ipef, .Isef, .fs, .Ts, .T (ambient temp degC)
%        .D (duty), .D2 (=1-D), .Rfio (ohm/cm @20C), .Afio (cm^2), .Dfio (cm)
%        .kumin, .kumax, .DeltaTmax
%        .Bm   peak flux density [T]
%        .J    current density [A/cm^2]
%        .kFaraday  waveform constant k in Np = Vd*1e4/(k*Bm*fs*Ae) (default 9)
%        .Fr   ac winding-loss factor, multiplies the dc copper loss (default 1)
%        .Pnucleomax, .Vmax    user caps
%   core - struct describing the core:
%        .partNumber .manufacturer .geometry ('R'|'EE')
%        .parallel    number of cores in parallel
%        .Ve_cm3 .Ae_cm2 .Ap_cm4 .OD_cm .ID_cm .H_cm
%        .Length_cm .LegLength_cm     (only for EE)
%   mat - Steinmetz row (struct from catalog.steinmetz)
%        .alpha .beta .k .c1_T .c2_T .c3_T .k_iGSE + .Material
%        k_iGSE is the GSE coefficient k1 of Li (2001), computed from k,
%        alpha and beta.
%
%   opts - optional:
%        .gseEnabled (default true) - core loss by the GSE; if false the
%                     classical Steinmetz value is used for both groups
%        .neuralNet  (TDK N27..N97): struct from load_neural_net with
%                     .materialIdx set. These ferrites have no Steinmetz
%                     coefficients in the catalog, so their core loss comes
%                     from the neural net for both groups.
%
%   The converter uses six transformers, three driven by the upper bridge
%   and three by the lower one. Both groups are evaluated (fields *Sup and
%   *Inf); Ptrafo is the upper-group unit loss and PtrafoInf the lower-group
%   one. Core and copper losses are coupled to the core temperature, which
%   is iterated with dT = (1000*P/Sa)^0.833 (P in W, Sa in cm^2).
%
%   Returns proj struct, or an all-NaN struct with .reason if rejected.

    if nargin < 4, opts = struct(); end
    if ~isfield(opts, 'gseEnabled'), opts.gseEnabled = true; end
    useNet = isfield(opts, 'neuralNet') && ~isempty(opts.neuralNet);

    % AC winding-loss factor; Fr = 1 means no extra ac correction
    Fr = 1;
    if isfield(D, 'Fr') && isscalar(D.Fr) && isfinite(D.Fr) && D.Fr >= 1
        Fr = D.Fr;
    end

    % --- Mean turn length [cm]
    if strcmp(core.geometry, 'EE')
        CEM = (2*core.Ae_cm2/core.H_cm + 2*core.H_cm) * 1.1;
    else
        CEM = (2*core.H_cm + (core.OD_cm - core.ID_cm)) * 1.1;
    end

    % --- Winding design (Faraday): Np for a given Bmax
    kFar = 9;
    if isfield(D, 'kFaraday') && D.kFaraday > 0, kFar = D.kFaraday; end
    Np = round((D.Vd * 1e4) / (kFar * D.Bm * D.fs * core.Ae_cm2));
    if ~isfinite(Np), proj = i_reject('geometry_incomplete'); return; end
    if Np <= 0, proj = i_reject('Np<=0'); return; end
    Ns = ceil(Np * D.n);

    Compfio_prim = Np * CEM;
    Compfio_sec  = Ns * CEM;
    Nfios_prim = ceil((D.Ipef / D.J) / D.Afio);
    Nfios_sec  = ceil((D.Isef / D.J) / D.Afio);

    Area_nec = Np*D.Afio*Nfios_prim + Ns*D.Afio*Nfios_sec;
    Vcu = Compfio_prim*D.Afio*Nfios_prim + Compfio_sec*D.Afio*Nfios_sec;
    Mcu = Vcu * 8.96;                          % [g] copper density 8.96 g/cm^3

    Aw_cm2 = core.Ap_cm4 / core.Ae_cm2;        % window area
    Ku = Area_nec / Aw_cm2;
    if Ku < D.kumin, proj = i_reject('Ku<kumin'); return; end
    if Ku > D.kumax, proj = i_reject('Ku>kumax'); return; end

    % --- Surface area for the temperature rise [cm^2]
    if strcmp(core.geometry, 'EE')
        Sa = 2 * (core.LegLength_cm*core.Length_cm + core.H_cm*core.LegLength_cm ...
                  + core.H_cm*core.Length_cm);
    else
        Sa = 2*pi*(core.OD_cm/2)^2 + 2*pi*core.OD_cm/4 * core.H_cm;
    end
    if ~isfinite(Sa) || ~isfinite(core.Ve_cm3)
        % Missing dimensions in the catalog (e.g. PQ cores without LegLength)
        proj = i_reject('geometry_incomplete'); return
    end

    % --- dc winding resistances at 20 degC
    Rp20 = D.Rfio * Compfio_prim / Nfios_prim;
    Rs20 = D.Rfio * Compfio_sec  / Nfios_sec;

    % --- Core and copper losses coupled to the core temperature. Fixed-point
    % iteration with under-relaxation: core loss and temperature feed each
    % other, and without relaxation the iteration can oscillate between a hot
    % and a cold state. Designs that do not settle are rejected.
    TcoreSup = D.T;  TcoreInf = D.T;
    DeltaTSup = 0;   DeltaTInf = 0;
    PcoreSup = NaN;  PcoreInf = NaN;
    PcondSup = NaN;  PcondInf = NaN;
    converged = false;
    for it = 1:60
        [PcoreSup, PcoreInf] = i_coreLoss(D, core, mat, opts, useNet, Np, TcoreSup, TcoreInf);
        if ~isfinite(PcoreSup) || ~isfinite(PcoreInf)
            proj = i_reject('core_loss_invalid'); return
        end
        PcondSup = Fr * (Rp20*D.Ipef^2 + Rs20*D.Isef^2) * (1 + 0.0038*(TcoreSup - 20));
        PcondInf = Fr * (Rp20*D.Ipef^2 + Rs20*D.Isef^2) * (1 + 0.0038*(TcoreInf - 20));

        DeltaTSup = (1000*(PcoreSup + PcondSup)/Sa)^0.833;
        DeltaTInf = (1000*(PcoreInf + PcondInf)/Sa)^0.833;
        stepSup = D.T + DeltaTSup - TcoreSup;
        stepInf = D.T + DeltaTInf - TcoreInf;
        if abs(stepSup) < 0.01 && abs(stepInf) < 0.01
            converged = true;
            break
        end
        TcoreSup = TcoreSup + 0.5*stepSup;
        TcoreInf = TcoreInf + 0.5*stepInf;
    end
    if ~converged
        proj = i_reject('thermal_no_convergence'); return
    end
    PtrafoSup = PcoreSup + PcondSup;
    PtrafoInf = PcoreInf + PcondInf;

    % Classical Steinmetz, kept only as a reference, at the same core temperature
    PnucleoSE = core.Ve_cm3 * i_seDensity(D, mat, opts, useNet, TcoreSup) / 1000;   % [W]

    % --- Total volume
    if strcmp(core.geometry, 'EE')
        Vtotal = core.Ve_cm3 + Vcu;           % approximation for EE cores
    else
        % Toroid: winding layers around the core, using the equivalent
        % bundle diameter of each winding
        dp = 2*sqrt(D.Afio*Nfios_prim/pi);
        ds = 2*sqrt(D.Afio*Nfios_sec/pi);
        Nrounds = round((Np*dp + Ns*ds) / (core.OD_cm*pi));
        Meand = (dp + ds) / 2;
        OD_ext = core.OD_cm + 2*Nrounds*Meand;
        H_ext  = core.H_cm  + 2*Nrounds*Meand;
        Vtotal = pi*(OD_ext/2)^2 * H_ext;
    end

    % --- Constraints (the upper group is the reference unit)
    if DeltaTSup > D.DeltaTmax, proj = i_reject('DeltaT>max'); return; end
    if isfield(D, 'Pnucleomax') && PtrafoSup > D.Pnucleomax, proj = i_reject('Ptrafo>Pmax'); return; end
    if isfield(D, 'Vmax') && Vtotal > D.Vmax, proj = i_reject('Vol>Vmax'); return; end

    proj = struct( ...
        'Manufacturer',  core.manufacturer, ...
        'Size',          core.partNumber, ...
        'Geometry',      core.geometry, ...
        'Material',      mat.Material, ...
        'ParallelCores', core.parallel, ...
        'Np',            Np, ...
        'Ns',            Ns, ...
        'NfiosPrim',     Nfios_prim, ...
        'NfiosSec',      Nfios_sec, ...
        'CompfioPrim',   Compfio_prim, ...
        'CompfioSec',    Compfio_sec, ...
        'PnucleoSE',     PnucleoSE, ...
        'PnucleoGSEsup', PcoreSup, ...
        'PnucleoGSEinf', PcoreInf, ...
        'PcondSup',      PcondSup, ...
        'PcondInf',      PcondInf, ...
        'Ptrafo',        PtrafoSup, ...
        'PtrafoInf',     PtrafoInf, ...
        'DeltaT',        DeltaTSup, ...
        'Tcore',         TcoreSup, ...
        'VolCore',       core.Ve_cm3, ...
        'VolTotal',      Vtotal, ...
        'Mcu',           Mcu, ...
        'J',             D.J, ...
        'Ku',            Ku, ...
        'Bm',            D.Bm, ...
        'Fr',            Fr);
end


function [Psup, Pinf] = i_coreLoss(D, core, mat, opts, useNet, Np, Tsup, Tinf)
% Core loss [W] of the upper and lower transformer groups.
    if useNet
        % TDK ferrites: neural-net Steinmetz loss, same for both groups
        Psup = core.Ve_cm3 * i_neuralNetEval(opts.neuralNet, D.fs, D.Bm, Tsup) / 1000;
        Pinf = core.Ve_cm3 * i_neuralNetEval(opts.neuralNet, D.fs, D.Bm, Tinf) / 1000;
    elseif opts.gseEnabled
        [Psup, Pinf] = i_gseLosses(D, core, mat, Np, Tsup, Tinf);
    else
        Psup = core.Ve_cm3 * i_seDensity(D, mat, opts, false, Tsup) / 1000;
        Pinf = core.Ve_cm3 * i_seDensity(D, mat, opts, false, Tinf) / 1000;
    end
end


function p = i_seDensity(D, mat, opts, useNet, T)
% Classical Steinmetz loss density [mW/cm^3] at temperature T.
    if useNet
        p = i_neuralNetEval(opts.neuralNet, D.fs, D.Bm, T);
    else
        p = (mat.k * (D.fs^mat.alpha) * (D.Bm^mat.beta) ...
             * (mat.c1_T - mat.c2_T*T + mat.c3_T*T^2)) / 1000;
    end
end


function [supGSE, infGSE] = i_gseLosses(D, core, mat, Np, Tsup, Tinf)
% Generalized Steinmetz losses [W] using the transformer voltage waveform:
% 6 segments for Vo > 480 V (1/3 < D < 2/3) and 3 segments for Vo <= 480 V
% (D <= 1/3). Returns NaN when the integrals would diverge.
    supGSE = NaN; infGSE = NaN;
    Aef = core.Ae_cm2 * 1e-4;                  % cm^2 -> m^2
    c = mat.beta - mat.alpha;
    if c <= -0.99
        % Integrand blows up at a*x+b=0, so skip the GSE in this case.
        return
    end
    try
        if D.Vo > 480
            infGSE = i_gseHexagonal(D, Np, Aef, mat, c, D.D,  Tinf);
            supGSE = i_gseHexagonal(D, Np, Aef, mat, c, D.D2, Tsup);
        else
            infGSE = i_gseTriangular(D, Np, Aef, mat, c, D.D, false, Tinf);
            supGSE = i_gseTriangular(D, Np, Aef, mat, c, D.D, true,  Tsup);
        end
    catch
        return
    end
    if ~isfinite(supGSE), supGSE = NaN; end
    if ~isfinite(infGSE), infGSE = NaN; end
    supGSE = core.Ve_cm3 * supGSE / 1e6;       % W/m^3 times cm^3 -> W
    infGSE = core.Ve_cm3 * infGSE / 1e6;
end


function P = i_gseHexagonal(D, Np, Aef, mat, c, dd, Tcore)
% B(t) = a_i*t + b_i on each segment, with t measured from the start of the
% period (the b_i are intercepts at t = 0). The six segments are contiguous,
% so segment i is integrated over [t_(i-1), t_i].
    k0 = D.Vd / (Np*Aef);
    a = [1 2 1 -1 -2 -1] * k0/3;
    b = [-1/9, -dd/3, -(3*dd-1)/9, (1+3*dd)/9, (1+dd)/3, 2/9] * k0*D.Ts;
    d1 = D.Ts*(3*dd-1)/3;
    d2 = D.Ts*(2-3*dd)/3;
    t = [0, cumsum([d1 d2 d1 d2 d1 d2])];
    s = 0;
    for i = 1:6
        s = s + abs(a(i))^mat.alpha * i_segIntegral(a(i), b(i), t(i), t(i+1), c);
    end
    P = (1/D.Ts) * mat.k_iGSE * s * (mat.c1_T - mat.c2_T*Tcore + mat.c3_T*Tcore^2);
end


function P = i_gseTriangular(D, Np, Aef, mat, c, dd, isUpper, Tcore)
% Three voltage pulses of length D*Ts starting at 0, Ts/3 and 2Ts/3, with
% zero voltage (flat flux, no GSE loss) between them. As in the hexagonal
% case, b_i are intercepts at t = 0.
    k0 = D.Vd / (Np*Aef);
    if isUpper
        a = [1 1 -2] * k0/3;
        b = [-dd/3, -1/9, (3*dd+4)/9] * k0*D.Ts;
    else
        a = [2 -1 -1] * k0/3;
        b = [-dd/3, (3*dd+1)/9, 2/9] * k0*D.Ts;
    end
    t0 = [0, 1/3, 2/3] * D.Ts;
    s = 0;
    for i = 1:3
        s = s + abs(a(i))^mat.alpha * i_segIntegral(a(i), b(i), t0(i), t0(i) + dd*D.Ts, c);
    end
    P = (1/D.Ts) * mat.k_iGSE * s * (mat.c1_T - mat.c2_T*Tcore + mat.c3_T*Tcore^2);
end


function v = i_segIntegral(a, b, t0, t1, c)
% Integral of |a*t + b|^c from t0 to t1 (c > -1). B is linear on the
% segment, so with u = a*t + b the antiderivative is sign(u)*|u|^(c+1)/(c+1)
% divided by a. Exact, and much faster than a numerical quadrature inside
% the temperature loop.
    if a == 0
        v = abs(b)^c * (t1 - t0);
        return
    end
    F = @(u) sign(u) .* abs(u).^(c+1) / (c+1);
    v = (F(a*t1 + b) - F(a*t0 + b)) / a;
end


function nPnucleoSE = i_neuralNetEval(net, fs, B, T)
% Forward pass through the TDK neural net (tansig hidden layers, linear
% output). Returns the loss density in mW/cm^3. The temperature is kept
% inside the training range of the net (25 to 120 degC): outside it the net
% extrapolates and can return losses close to zero.
    i1 = net.materialIdx;
    T = min(max(T, net.min_t(i1)), net.max_t(i1));
    Freq_norm = 2*(fs/1000 - net.min_freq(i1)) / (net.max_freq(i1) - net.min_freq(i1)) - 1;
    B_norm    = 2*(B*1000  - net.min_b(i1))    / (net.max_b(i1)    - net.min_b(i1))    - 1;
    Temp_norm = 2*(T       - net.min_t(i1))    / (net.max_t(i1)    - net.min_t(i1))    - 1;
    if isnan(Temp_norm), Temp_norm = -1; end

    x = [Freq_norm; B_norm; Temp_norm];
    Wmat = net.w(i1).matrices;
    bArr = net.b(i1).array;
    nLayers = numel(Wmat);
    for p = 1:nLayers
        z = Wmat(p).matrices * x + bArr(p).array;
        if p < nLayers
            x = i_tansig(z);    % hidden layers
        else
            x = z;              % linear output layer
        end
    end
    nPnucleoSE = 10.^(((x + 1) .* (net.max_out(i1) - net.min_out(i1))) / 2 + net.min_out(i1));
end


function y = i_tansig(x)
% Hyperbolic tangent sigmoid, written out so the app does not need the
% Deep Learning Toolbox (where tansig lives).
    y = 2 ./ (1 + exp(-2 .* x)) - 1;
end


function p = i_reject(reason)
    if nargin < 1, reason = 'unknown'; end
    p = struct('Manufacturer','','Size','','Geometry','','Material','', ...
        'ParallelCores',NaN,'Np',NaN,'Ns',NaN,'NfiosPrim',NaN,'NfiosSec',NaN, ...
        'CompfioPrim',NaN,'CompfioSec',NaN,'PnucleoSE',NaN,'PnucleoGSEsup',NaN, ...
        'PnucleoGSEinf',NaN,'PcondSup',NaN,'PcondInf',NaN,'Ptrafo',NaN,'PtrafoInf',NaN, ...
        'DeltaT',NaN,'Tcore',NaN,'VolCore',NaN,'VolTotal',NaN,'Mcu',NaN,'J',NaN, ...
        'Ku',NaN,'Bm',NaN,'Fr',NaN,'reason',reason);
end
