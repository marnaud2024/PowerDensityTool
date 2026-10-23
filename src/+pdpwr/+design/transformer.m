function proj = transformer(D, core, mat, opts)
%TRANSFORMER Single-design transformer evaluation
%
% Thermal coupled GSE version:
% Core losses are updated with core temperature feedback.

    if nargin < 4
        opts = struct();
    end

    if ~isfield(opts,'gseEnabled')
        opts.gseEnabled = true;
    end

    % User-defined AC winding-loss factor. Fr = 1 means no extra AC-loss correction.
    Fr = 1;
    if isfield(D,'Fr') && isscalar(D.Fr) && isfinite(D.Fr) && D.Fr >= 1
        Fr = D.Fr;
    end


    %% ============================================================
    % Geometry helpers
    % =============================================================

    if strcmp(core.geometry,'EE')

        CEM = (2*core.Ae_cm2/core.H_cm + 2*core.H_cm)*1.1;

    else

        CEM = (2*core.H_cm + ...
              (core.OD_cm-core.ID_cm))*1.1;

    end



    %% ============================================================
    % Winding design
    % =============================================================

    kFar = 9;

    if isfield(D,'kFaraday') && D.kFaraday > 0
        kFar = D.kFaraday;
    end


    Np = round((D.Vd*1e4)/(kFar*D.Bm*D.fs*core.Ae_cm2));

    if Np <= 0
        proj = i_reject('Np<=0');
        return
    end


    Ns = ceil(Np*D.n);


    Compfio_prim = Np*CEM;
    Compfio_sec  = Ns*CEM;


    Scu_prim = D.Ipef/D.J;
    Scu_sec  = D.Isef/D.J;


    Nfios_prim = ceil(Scu_prim/D.Afio);
    Nfios_sec  = ceil(Scu_sec/D.Afio);



    Area_nec = Np*D.Afio*Nfios_prim + ...
               Ns*D.Afio*Nfios_sec;


    Vcu = Compfio_prim*D.Afio*Nfios_prim + ...
          Compfio_sec*D.Afio*Nfios_sec;


    Mcu = Vcu*8.96;



    Aw_cm2 = core.Ap_cm4/core.Ae_cm2;


    Ku = Area_nec/Aw_cm2;


    if Ku < D.kumin
        proj = i_reject('Ku<kumin');
        return
    end


    if Ku > D.kumax
        proj = i_reject('Ku>kumax');
        return
    end



    %% ============================================================
    % Surface area thermal model
    % =============================================================

    if strcmp(core.geometry,'EE')

        Sa = 2*( ...
            core.LegLength_cm*core.Length_cm + ...
            core.H_cm*core.LegLength_cm + ...
            core.H_cm*core.Length_cm);

    else

        Sa = 2*pi*(core.OD_cm/2)^2 + ...
             2*pi*core.OD_cm/4*core.H_cm;

    end



    %% ============================================================
    % Initial temperature
    % =============================================================

    TcoreSup = D.T;
    TcoreInf = D.T;

    DeltaTSup = 0;
    DeltaTInf = 0;



    %% ============================================================
    % Initial copper resistance
    % =============================================================

    Rp = D.Rcfio*Compfio_prim/Nfios_prim;
    Rs = D.Rcfio*Compfio_sec/Nfios_sec;


    PcondSup = Fr * (Rp*D.Ipef^2 + Rs*D.Isef^2);
    PcondInf = PcondSup;



    %% ============================================================
    % Conventional Steinmetz reference
    % =============================================================

    nPnucleoSE = (mat.k * (D.fs^mat.alpha) * (D.Bm^mat.beta) ...
                 * (mat.c1_T - mat.c2_T*D.T + mat.c3_T*D.T^2))/1000;

    PnucleoSE = core.Ve_cm3*nPnucleoSE/1000;


    %% ============================================================
    % Thermal coupled GSE iteration
    % =============================================================

    for it = 1:7
        % --------------------------------------------------------
        % Core losses with updated temperature
        % --------------------------------------------------------

        if opts.gseEnabled
            [supPnucleoGSE, infPnucleoGSE] = i_gseLosses(D,core,mat,TcoreSup,TcoreInf);
        else
            supPnucleoGSE = PnucleoSE;
            infPnucleoGSE = PnucleoSE;
        end
        PcoreSup = supPnucleoGSE;
        PcoreInf = infPnucleoGSE;

        % Total losses
        PtrafoSup = PcondSup + PcoreSup;
        PtrafoInf = PcondInf + PcoreInf;

        % Temperature update
        DeltaTSup = (1000*PtrafoSup/Sa)^0.833;
        DeltaTInf = (1000*PtrafoInf/Sa)^0.833;

        TcoreSup = D.T + DeltaTSup;
        TcoreInf = D.T + DeltaTInf;

        % --------------------------------------------------------
        % Copper resistance update
        % --------------------------------------------------------

        RcfioSup = D.Rfio*(1+0.0038*(TcoreSup-20));
        RcfioInf = D.Rfio*(1+0.0038*(TcoreInf-20));

        Rpsup = RcfioSup*Compfio_prim/Nfios_prim;
        Rssup = RcfioSup*Compfio_sec/Nfios_sec;


        Rpinf = RcfioInf*Compfio_prim/Nfios_prim;
        Rsinf = RcfioInf*Compfio_sec/Nfios_sec;


        PcondSup = Fr * (Rpsup*D.Ipef^2 + Rssup*D.Isef^2);
        PcondInf = Fr * (Rpinf*D.Ipef^2 + Rsinf*D.Isef^2);

    end
    %% ============================================================
    % Final values
    % =============================================================

    Ptrafo = PtrafoSup;
    DeltaT = DeltaTSup;

    % Final core losses
    PnucleoGSEsup = PcoreSup;
    PnucleoGSEinf = PcoreInf;


    %% ============================================================
    % Total physical volume
    % =============================================================

    if strcmp(core.geometry,'EE')
        % Approximation for EE cores
        Vtotal = core.Ve_cm3 + Vcu;
    else
        % Toroidal external volume
        Nrounds = round( ...
            (Np*2*sqrt(D.Afio*Nfios_prim/pi) + ...
             Ns*2*sqrt(D.Afio*Nfios_sec/pi)) / ...
             (core.OD_cm*pi));

        Meand = ...
            (2*sqrt(D.Afio*Nfios_prim/pi) + ...
             2*sqrt(D.Afio*Nfios_sec/pi))/2;

        OD_ext = core.OD_cm + 2*Nrounds*Meand;
        H_ext = core.H_cm + 2*Nrounds*Meand;
        Vtotal = pi*(OD_ext/2)^2*H_ext;
    end


    %% ============================================================
    % Constraints
    % =============================================================

    if DeltaT > D.DeltaTmax
        proj = i_reject('DeltaT>max');
        return
    end


    if isfield(D,'Pnucleomax') && Ptrafo > D.Pnucleomax
        proj = i_reject('Ptrafo>Pmax');
        return
    end


    if isfield(D,'Vmax') && Vtotal > D.Vmax
        proj = i_reject('Vol>Vmax');
        return
    end

    %% ============================================================
    % Output structure
    % =============================================================

    proj = struct();

    proj.Manufacturer = core.manufacturer;
    proj.Size = core.partNumber;
    proj.Geometry = core.geometry;
    proj.Material = mat.Material;

    proj.ParallelCores = core.parallel;

    proj.Np = Np;
    proj.Ns = Ns;

    proj.NfiosPrim = Nfios_prim;
    proj.NfiosSec = Nfios_sec;

    proj.CompfioPrim = Compfio_prim;
    proj.CompfioSec = Compfio_sec;

    proj.PnucleoSE = PnucleoSE;
    proj.PnucleoGSEsup = PnucleoGSEsup;
    proj.PnucleoGSEinf = PnucleoGSEinf;

    proj.PcondSup = PcondSup;
    proj.PcondInf = PcondInf;

    proj.Ptrafo = Ptrafo;
    proj.PtrafoInf = PtrafoInf;

    proj.DeltaT = DeltaT;
    proj.Tcore = TcoreSup;

    proj.VolCore = core.Ve_cm3;
    proj.VolTotal = Vtotal;

    proj.Mcu = Mcu;

    proj.J = D.J;
    proj.Ku = Ku;
    proj.Bm = D.Bm;
    proj.Fr = Fr;

end

function [supGSE, infGSE] = i_gseLosses(D, core, mat, TcoreSup, TcoreInf)
% Generalized Steinmetz losses using the inverter waveform.
% Temperature coupled version.
%
% TcoreSup / TcoreInf:
%   Core temperature for upper/lower thermal conditions [degC]


    supGSE = NaN;
    infGSE = NaN;


    Ae_factor = core.Ae_cm2 * 1e-4;   % cm² -> m²


    kFar = 9;

    if isfield(D,'kFaraday') && D.kFaraday > 0
        kFar = D.kFaraday;
    end


    Np = round((D.Vd*1e4)/(kFar*D.Bm*D.fs*core.Ae_cm2));


    if Np <= 0
        return
    end


    c = mat.beta - mat.alpha;


    if c <= -0.99
        return
    end



    try

        if D.Vo > 480


            infGSE = i_gseHexagonal( ...
                D, Np, Ae_factor, mat, c, D.D, TcoreInf);


            supGSE = i_gseHexagonal( ...
                D, Np, Ae_factor, mat, c, D.D2, TcoreSup);



        else

            infGSE = i_gseTriangular( ...
                D, Np, Ae_factor, mat, c, D.D, false, TcoreInf);


            supGSE = i_gseTriangular( ...
                D, Np, Ae_factor, mat, c, D.D, true, TcoreSup);

        end


    catch

        return

    end



    if ~isfinite(supGSE)
        supGSE = NaN;
    end


    if ~isfinite(infGSE)
        infGSE = NaN;
    end

    % Convert volumetric loss to total core loss
    supGSE = core.Ve_cm3 * supGSE / 1e6;

    infGSE = core.Ve_cm3 * infGSE / 1e6;


end

function P = i_gseHexagonal(D, Np, Aef, mat, c, dd, Tcore)


    a1 =  D.Vd/(3*Np*Aef);
    a2 =  2*D.Vd/(3*Np*Aef);
    a3 =  D.Vd/(3*Np*Aef);

    a4 = -D.Vd/(3*Np*Aef);
    a5 = -2*D.Vd/(3*Np*Aef);
    a6 = -D.Vd/(3*Np*Aef);



    b1 = -D.Vd*D.Ts/(9*Np*Aef);

    b2 = -D.Vd*D.Ts*dd/(3*Np*Aef);

    b3 = -D.Vd*D.Ts*(3*dd-1)/(9*Np*Aef);

    b4 = D.Vd*D.Ts*(1+3*dd)/(9*Np*Aef);

    b5 = D.Vd*D.Ts*(1+dd)/(3*Np*Aef);

    b6 = 2*D.Vd*D.Ts/(9*Np*Aef);



    d1 = D.Ts*(3*dd-1)/3;
    d2 = D.Ts*(2-3*dd)/3;

    d3 = d1;

    d4 = d2;

    d5 = d1;

    d6 = d2;

    seg = @(a,b,d) abs(a)^mat.alpha * integral(@(x)abs(a*x+b).^c,0,d);

    P = (1/D.Ts)*mat.k_iGSE* ...
        ( ...
        seg(a1,b1,d1)+ ...
        seg(a2,b2,d2)+ ...
        seg(a3,b3,d3)+ ...
        seg(a4,b4,d4)+ ...
        seg(a5,b5,d5)+ ...
        seg(a6,b6,d6) ...
        ) ...
        * ...
        (mat.c1_T - mat.c2_T*Tcore + mat.c3_T*Tcore^2);
end


function P = i_gseTriangular(D, Np, Aef, mat, c, dd, isUpper, Tcore)


    if isUpper

        a1 = D.Vd/(3*Np*Aef);

        a2 = D.Vd/(3*Np*Aef);

        a3 = -2*D.Vd/(3*Np*Aef);

        b1 = -D.Vd*dd*D.Ts/(3*Np*Aef);

        b2 = -D.Vd*D.Ts/(9*Np*Aef);

        b3 = D.Vd*D.Ts*(3*dd+4)/(9*Np*Aef);

    else

        a1 = 2*D.Vd/(3*Np*Aef);
        a2 = -D.Vd/(3*Np*Aef);
        a3 = -D.Vd/(3*Np*Aef);


        b1 = -D.Vd*dd*D.Ts/(3*Np*Aef);
        b2 = D.Vd*D.Ts*(3*dd+1)/(9*Np*Aef);
        b3 = 2*D.Vd*D.Ts/(9*Np*Aef);

    end



    d = dd*D.Ts;


    seg = @(a,b) ...
        abs(a)^mat.alpha * ...
        integral(@(x)abs(a*x+b).^c,0,d);


    P = (1/D.Ts)*mat.k_iGSE* ...
        (seg(a1,b1)+seg(a2,b2)+seg(a3,b3)) ...
        * ...
        (mat.c1_T - mat.c2_T*Tcore + mat.c3_T*Tcore^2);


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
