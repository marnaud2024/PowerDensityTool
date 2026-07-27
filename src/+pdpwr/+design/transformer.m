function proj = transformer(D, core, mat, opts)
%TRANSFORMER Single-design transformer evaluation (Magnetics / TDK / Magmattec cores).
%
%   proj = pdpwr.design.transformer(D, core, mat)
%   proj = pdpwr.design.transformer(D, core, mat, opts)
%
%   D    - design struct:
%        .Vd, .Vo, .n, .Ipef, .Isef, .fs, .Ts, .T (ambient temp degC)
%        .D (duty), .D2 (=1-D), .Rfio (ohm/cm @20C), .Afio (cm^2), .Dfio (cm)
%        .Rcfio (ohm/cm at T), .kumin, .kumax, .DeltaTmax
%        .Bm   peak flux density [T]
%        .J    current density [A/cm^2]
%        .Pnucleomax, .Vmax    user caps
%   core - struct describing the core:
%        .partNumber .manufacturer .geometry ('R'|'EE')
%        .parallel    number of cores in parallel
%        .Ve_cm3 .Ae_cm2 .Ap_cm4 .OD_cm .ID_cm .H_cm
%        .Length_cm .LegLength_cm     (only for EE)
%   mat - Steinmetz coefficient row (struct from catalog.steinmetz)
%        .alpha .beta .k .c1_T .c2_T .c3_T  + .Material string
%
%   opts - optional:
%        .gseEnabled (default true) - compute upper/lower GSE losses
%        .neuralNet  (optional, only for TDK N27..N97):
%                     struct from a loaded w/b .mat with .min_b .max_b .min_freq
%                     .max_freq .min_t .max_t .min_out .max_out .w .b and .materialIdx
%
%   Returns proj struct or NaN-only struct if invalid.

    if nargin < 4, opts = struct(); end
    if ~isfield(opts, 'gseEnabled'), opts.gseEnabled = true; end

    % --- Common geometry helpers
    if strcmp(core.geometry, 'EE')
        CEM = (2*core.Ae_cm2/core.H_cm + 2*core.H_cm) * 1.1;     % [cm] mean turn length
    else
        CEM = (2*core.H_cm + (core.OD_cm - core.ID_cm)) * 1.1;   % [cm] mean turn length toroid
    end

    % --- Winding design: Faraday (Np for a given Bmax). The waveform constant k
    % is user-set (D.kFaraday): 4=square wave, 4.44=sine, 9=this 3-level inverter.
    kFar = 9;
    if isfield(D, 'kFaraday') && D.kFaraday > 0, kFar = D.kFaraday; end
    Np = round( (D.Vd * 1e4) / (kFar * D.Bm * D.fs * core.Ae_cm2) );
    if Np <= 0, proj = i_reject('Np<=0'); return; end
    Ns = ceil(Np * D.n);

    Compfio_prim = Np * CEM;
    Compfio_sec  = Ns * CEM;
    Scu_prim = D.Ipef / D.J;
    Scu_sec  = D.Isef / D.J;
    Nfios_prim = ceil(Scu_prim / D.Afio);
    Nfios_sec  = ceil(Scu_sec  / D.Afio);

    Area_nec = Np * D.Afio * Nfios_prim + Ns * D.Afio * Nfios_sec;
    Vcu = Compfio_prim * D.Afio * Nfios_prim + Compfio_sec * D.Afio * Nfios_sec;
    Mcu = Vcu * 8.96;       % [g] copper density 8.96 g/cm^3

    Aw_cm2 = core.Ap_cm4 / core.Ae_cm2;     % window area available
    Ku = Area_nec / Aw_cm2;
    if Ku < D.kumin, proj = i_reject('Ku<kumin'); return; end
    if Ku > D.kumax, proj = i_reject('Ku>kumax'); return; end

    % --- Core loss
    if isfield(opts, 'neuralNet') && ~isempty(opts.neuralNet)
        % TDK ferrites: feed-forward neural net predicting Steinmetz core loss
        nPnucleoSE = i_neuralNetEval(opts.neuralNet, D.fs, D.Bm, D.T);
    else
        % Magnetics / Magmattec: classical Steinmetz polynomial
        nPnucleoSE = (mat.k * (D.fs^mat.alpha) * (D.Bm^mat.beta) ...
                      * (mat.c1_T - mat.c2_T*D.T + mat.c3_T*D.T^2)) / 1000;
    end
    PnucleoSE = core.Ve_cm3 * nPnucleoSE / 1000;   % [W]

    % --- Generalized Steinmetz (upper/lower duty) - identical math to legacy
    supPnucleoGSE = NaN;
    infPnucleoGSE = NaN;
    if opts.gseEnabled
        [supPnucleoGSE, infPnucleoGSE] = i_gseLosses(D, core, mat);
    end

    % --- Iterative copper loss with temperature feedback (5 inner iterations)
    Rp = D.Rcfio * Compfio_prim / Nfios_prim;
    Rs = D.Rcfio * Compfio_sec  / Nfios_sec;
    Pcond = Rp * D.Ipef^2 + Rs * D.Isef^2;
    if strcmp(core.geometry, 'EE')
        Sa = 2 * (core.LegLength_cm*core.Length_cm + core.H_cm*core.LegLength_cm + core.H_cm*core.Length_cm);
    else
        Sa = 2*pi*(core.OD_cm/2)^2 + 2*pi*core.OD_cm/4 * core.H_cm;
    end
    DeltaT = 0;
    Rcfio = D.Rcfio;
    for it = 1:5
        Ptrafo = Pcond + PnucleoSE;
        DeltaT = (1000 * Ptrafo / Sa)^0.833;
        Rcfio = D.Rfio * (1 + 0.0038*(DeltaT + D.T - 20));
        Rp = Rcfio * Compfio_prim / Nfios_prim;
        Rs = Rcfio * Compfio_sec  / Nfios_sec;
        Pcond = Rp * D.Ipef^2 + Rs * D.Isef^2;
    end
    Ptrafo = Pcond + PnucleoSE;
    DeltaT = (1000 * Ptrafo / Sa)^0.833;

    Vtotal = core.Ve_cm3 + Vcu;

    if DeltaT > D.DeltaTmax, proj = i_reject('DeltaT>max'); return; end
    if isfield(D, 'Pnucleomax') && Ptrafo > D.Pnucleomax, proj = i_reject('Ptrafo>Pmax'); return; end
    if isfield(D, 'Vmax') && Vtotal > D.Vmax, proj = i_reject('Vol>Vmax'); return; end

    proj = struct( ...
        'Manufacturer',     core.manufacturer, ...
        'Size',             core.partNumber, ...
        'Geometry',         core.geometry, ...
        'Material',         mat.Material, ...
        'ParallelCores',    core.parallel, ...
        'Np',               Np, ...
        'Ns',               Ns, ...
        'NfiosPrim',        Nfios_prim, ...
        'NfiosSec',         Nfios_sec, ...
        'CompfioPrim',      Compfio_prim, ...
        'CompfioSec',       Compfio_sec, ...
        'PnucleoSE',        PnucleoSE, ...
        'supPnucleoGSE',    supPnucleoGSE, ...
        'infPnucleoGSE',    infPnucleoGSE, ...
        'Pcond',            Pcond, ...
        'Ptrafo',           Ptrafo, ...
        'DeltaT',           DeltaT, ...
        'VolCore',          core.Ve_cm3, ...
        'VolTotal',         Vtotal, ...
        'Mcu',              Mcu, ...
        'J',                D.J, ...
        'Ku',               Ku, ...
        'Bm',               D.Bm);
end


function [supGSE, infGSE] = i_gseLosses(D, core, mat)
% Generalized Steinmetz losses using the 6-segment three-level inverter waveform
% (Vo > 480 V) or the 3-segment waveform (Vo <= 480 V). Same math as legacy.
% Returns NaN when Np <= 0 or the GSE integrals would diverge.
    supGSE = NaN; infGSE = NaN;
    Ae_factor = core.Ae_cm2 * 1e-4;          % cm^2 -> m^2 (used as Ae/1e4 in legacy)
    kFar = 9;
    if isfield(D, 'kFaraday') && D.kFaraday > 0, kFar = D.kFaraday; end
    Np = round( (D.Vd * 1e4) / (kFar * D.Bm * D.fs * core.Ae_cm2) );
    if Np <= 0, return; end
    c = mat.beta - mat.alpha;
    if c <= -0.99
        % Integrand blows up at a*x+b=0, so skip the GSE in this case.
        return
    end

    try
        if D.Vo > 480
            infGSE = i_gseHexagonal(D, Np, Ae_factor, mat, c, D.D);
            supGSE = i_gseHexagonal(D, Np, Ae_factor, mat, c, D.D2);
        else
            infGSE = i_gseTriangular(D, Np, Ae_factor, mat, c, D.D, false);
            supGSE = i_gseTriangular(D, Np, Ae_factor, mat, c, D.D, true);
        end
    catch
        return
    end
    if ~isfinite(supGSE), supGSE = NaN; end
    if ~isfinite(infGSE), infGSE = NaN; end
    % Multiply by volume / unit factors identical to legacy app2
    supGSE = core.Ve_cm3 * supGSE / 1e6;
    infGSE = core.Ve_cm3 * infGSE / 1e6;
end


function P = i_gseHexagonal(D, Np, Aef, mat, c, dd)
    a1 =  D.Vd        / (3*Np*Aef);
    a2 =  2*D.Vd      / (3*Np*Aef);
    a3 =  D.Vd        / (3*Np*Aef);
    a4 = -D.Vd        / (3*Np*Aef);
    a5 = -2*D.Vd      / (3*Np*Aef);
    a6 = -D.Vd        / (3*Np*Aef);

    b1 = -D.Vd*D.Ts          / (9*Np*Aef);
    b2 = -D.Vd*D.Ts*dd       / (3*Np*Aef);
    b3 = -D.Vd*D.Ts*(3*dd-1) / (9*Np*Aef);
    b4 =  D.Vd*D.Ts*(1+3*dd) / (9*Np*Aef);
    b5 =  D.Vd*D.Ts*(1+dd)   / (3*Np*Aef);
    b6 =  2*D.Vd*D.Ts        / (9*Np*Aef);

    d1 = D.Ts*(3*dd-1)/3;   d2 = D.Ts*(2-3*dd)/3;
    d3 = d1;                d4 = d2;
    d5 = d1;                d6 = d2;

    seg = @(a, b, d) abs(a)^mat.alpha * integral(@(x) abs(a*x + b).^c, 0, d);

    P = (1/D.Ts) * mat.k * ( seg(a1,b1,d1) + seg(a2,b2,d2) + seg(a3,b3,d3) ...
                           + seg(a4,b4,d4) + seg(a5,b5,d5) + seg(a6,b6,d6) ) ...
        * (mat.c1_T - mat.c2_T*D.T + mat.c3_T*D.T^2);
end


function P = i_gseTriangular(D, Np, Aef, mat, c, dd, isUpper)
    if isUpper
        a1 =  D.Vd        / (3*Np*Aef);
        a2 =  D.Vd        / (3*Np*Aef);
        a3 = -2*D.Vd      / (3*Np*Aef);
        b1 = -D.Vd*dd*D.Ts        / (3*Np*Aef);
        b2 = -D.Vd*D.Ts           / (9*Np*Aef);
        b3 =  D.Vd*D.Ts*(3*dd+4)  / (9*Np*Aef);
    else
        a1 =  2*D.Vd      / (3*Np*Aef);
        a2 = -D.Vd        / (3*Np*Aef);
        a3 = -D.Vd        / (3*Np*Aef);
        b1 = -D.Vd*dd*D.Ts        / (3*Np*Aef);
        b2 =  D.Vd*D.Ts*(3*dd+1)  / (9*Np*Aef);
        b3 =  2*D.Vd*D.Ts         / (9*Np*Aef);
    end
    d = dd * D.Ts;
    seg = @(a, b) abs(a)^mat.alpha * integral(@(x) abs(a*x + b).^c, 0, d);
    P = (1/D.Ts) * mat.k * (seg(a1,b1) + seg(a2,b2) + seg(a3,b3)) ...
        * (mat.c1_T - mat.c2_T*D.T + mat.c3_T*D.T^2);
end


function nPnucleoSE = i_neuralNetEval(net, fs, B, T)
% Forward pass through the TDK neural net (tansig hidden layers, linear output)
    i1 = net.materialIdx;
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
% Hyperbolic tangent sigmoid - self-contained so the app does NOT require
% the Deep Learning / Neural Network Toolbox (where tansig lives).
    y = 2 ./ (1 + exp(-2 .* x)) - 1;
end


function p = i_reject(reason)
    if nargin < 1, reason = 'unknown'; end
    p = struct('Manufacturer','','Size','','Geometry','','Material','', ...
        'ParallelCores',NaN,'Np',NaN,'Ns',NaN,'NfiosPrim',NaN,'NfiosSec',NaN, ...
        'CompfioPrim',NaN,'CompfioSec',NaN,'PnucleoSE',NaN,'supPnucleoGSE',NaN, ...
        'infPnucleoGSE',NaN,'Pcond',NaN,'Ptrafo',NaN,'DeltaT',NaN,'VolCore',NaN, ...
        'VolTotal',NaN,'Mcu',NaN,'J',NaN,'Ku',NaN,'Bm',NaN,'reason',reason);
end
