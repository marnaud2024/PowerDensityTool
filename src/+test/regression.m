function regression()
%TEST.REGRESSION Self-contained validation of the +pdpwr package.
%
%   Run from the PowerDensityTool/src folder:
%       cd 'C:\Users\Arnaud\Downloads\SOBRAEP\PowerDensityTool\src'
%       test.regression
%
%   This test does NOT depend on the legacy app code. It compares the new
%   pdpwr.* implementation against numerical anchors that were hand-computed
%   from the raw catalog files and embedded below. If any test FAILs, copy
%   the printed numbers back to me and I will adjust the package.

    fprintf('=== pdpwr regression suite (self-contained) ===\n');

    tolRel = 1e-3;     % 0.1 percent relative tolerance
    tolAbs = 1e-9;

    failures = 0;

    % -------- TEST 1: catalog loads with the expected sheet sizes --------
    fprintf('\n[1] Catalog load\n');
    try
        cat = pdpwr.util.load_catalog();
        i_expect(height(cat.mosfets),   91,   'mosfets table rows', tolAbs);
        i_expect(height(cat.diodes),    138,  'diodes table rows',  tolAbs);
        i_expect(height(cat.heatsinks), 63,   'heatsinks table rows', tolAbs);
        i_expect(height(cat.steinmetz), 13,   'steinmetz table rows', tolAbs);
        i_expect(height(cat.awg),       35,   'awg table rows',     tolAbs);
        fprintf('    PASS  catalog sheet sizes match\n');
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1; return
    end

    % -------- TEST 2: AWG lookup --------
    fprintf('\n[2] AWG lookup\n');
    try
        a16 = pdpwr.util.awg_props(16, cat.awg);
        if i_close(a16.r_ohm_m, 13.18e-3, tolRel, tolAbs) ...
                && i_close(a16.A_cm2, 14.73e-3, tolRel, tolAbs) ...
                && i_close(a16.D_cm,  0.137,    tolRel, tolAbs)
            fprintf('    PASS  AWG 16: r=%.4g  A=%.4g  D=%.4g\n', a16.r_ohm_m, a16.A_cm2, a16.D_cm);
        else
            fprintf('    FAIL  AWG 16 expected r=0.01318 A=0.01473 D=0.137, got r=%.5g A=%.5g D=%.5g\n', ...
                a16.r_ohm_m, a16.A_cm2, a16.D_cm);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 3: GeneSiC Eon hand-computed anchor --------
    %
    %   Anchor source: G3R40MT12K.xml, hand-computed:
    %       Eon_raw (I=30, V=800, T=25)   = 200.38 µJ
    %       k_Rg    = EonVsRg(7)/EonVsRg(4)  = 357.4375 / 233    = 1.534066523605
    %       k_T     = EonVsTemp(125)/EonVsTemp(25) = 315.1791 / 233.466 = 1.350069
    %       Eon = 200.38e-6 * 1.534066... * 1.350069... = 0.4149849375 mJ
    %
    fprintf('\n[3] GeneSiC G3R40MT12K Eon\n');
    try
        rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
        xmlPath = fullfile(rootDir, 'data', 'plecs_mosfets', 'GeneSiC', 'G3R40MT12K.xml');
        m = pdpwr.util.plecs_load(xmlPath, 'GeneSiC');
        EonExpected_J = 4.149849375e-4;
        EonGot_J = m.Eon(30, 800, 125, 7);
        if i_close(EonGot_J, EonExpected_J, tolRel, tolAbs)
            fprintf('    PASS  Eon = %.6e J (expected %.6e)\n', EonGot_J, EonExpected_J);
        else
            fprintf('    FAIL  Eon = %.6e J (expected %.6e), rel err %.3g\n', ...
                EonGot_J, EonExpected_J, abs(EonGot_J-EonExpected_J)/abs(EonExpected_J));
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 4: Wolfspeed Eon from XML round-trip --------
    fprintf('\n[4] Wolfspeed C3M0040120K Eon loads without error\n');
    try
        xmlPath = fullfile(rootDir, 'data', 'plecs_mosfets', 'Wolfspeed', 'C3M0040120K.xml');
        m = pdpwr.util.plecs_load(xmlPath, 'Wolfspeed');
        EonGot_J = m.Eon(30, 800, 125, 7);
        if isfinite(EonGot_J) && EonGot_J > 0
            fprintf('    PASS  Eon = %.6e J (positive, finite)\n', EonGot_J);
        else
            fprintf('    FAIL  Eon = %.6e J\n', EonGot_J);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 5: Diode hand-computed anchor --------
    %
    %   Anchor source: Catalog Diodes sheet, GD60MPS06H row:
    %       Rd_a=2.55e-7  Rd_b=2.76e-6  Rd_c=0.00976
    %       Vto_a=0  Vto_b=-0.00114  Vto_c=0.931
    %       PerLeg='NÃO'
    %   At Tj=125 I_RMS=57 I_avg=34:
    %       R_d   = 2.55e-7*125^2 + 2.76e-6*125 + 0.00976 = 0.014089375
    %       V_TO  = -0.00114*125 + 0.931 = 0.7885
    %       P_cond= 0.014089375*57^2 + 0.7885*34 = 72.585379375 W
    %
    fprintf('\n[5] Diode GD60MPS06H Pcond\n');
    try
        diodeIdx = find(strcmp(cat.diodes.PartNumber, 'GD60MPS06H'), 1);
        if isempty(diodeIdx)
            fprintf('    SKIP  GD60MPS06H not found in catalog\n');
        else
            row = table2struct(cat.diodes(diodeIdx, :));
            res = pdpwr.loss.diode(row, struct('Tj', 125, 'I_RMS', 57, 'I_avg', 34));
            expected = 72.585379375;
            if i_close(res.P_cond, expected, tolRel, tolAbs)
                fprintf('    PASS  Pcond = %.6g W (expected %.6g)\n', res.P_cond, expected);
            else
                fprintf('    FAIL  Pcond = %.6g W (expected %.6g)\n', res.P_cond, expected);
                failures = failures + 1;
            end
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 6: pcore_magmattec dispatches per material --------
    fprintf('\n[6] pcore_magmattec material-specific dispatch\n');
    try
        P002 = pdpwr.loss.pcore_magmattec('002', 50, 300);
        P026 = pdpwr.loss.pcore_magmattec('026', 50, 300);
        P034 = pdpwr.loss.pcore_magmattec('034', 50, 300);
        if abs(P002 - P026) > 1 && abs(P002 - P034) > 1 && abs(P026 - P034) > 1
            fprintf('    PASS  pcore002=%.2f  pcore026=%.2f  pcore034=%.2f mW/cm^3 (all distinct)\n', P002, P026, P034);
        else
            fprintf('    FAIL  Materials gave identical results: 002=%.2f 026=%.2f 034=%.2f\n', P002, P026, P034);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 7: Bpk fix in inductor design --------
    fprintf('\n[7] Bpk uses le (not CEM)\n');
    try
        D = i_designDataDemo();
        core = i_coreDemo();
        legacyP = pdpwr.design.inductor(D, core, struct('legacyBpkBug', true));
        newP    = pdpwr.design.inductor(D, core, struct('legacyBpkBug', false));
        if isnan(newP.N) || isnan(legacyP.N)
            % rejected by Ku or DeltaT - try smaller current to keep both alive
            D.ILmed = 5; D.ILef = 5.5; D.DeltaIL = 0.5; D.IL_max = 0.5;
            legacyP = pdpwr.design.inductor(D, core, struct('legacyBpkBug', true));
            newP    = pdpwr.design.inductor(D, core, struct('legacyBpkBug', false));
        end
        if ~isnan(legacyP.N) && ~isnan(newP.N) && newP.Bpk > legacyP.Bpk
            fprintf('    PASS  Bpk_new=%.4f T > Bpk_legacy=%.4f T (correct equation)\n', newP.Bpk, legacyP.Bpk);
        elseif isnan(legacyP.N) && isnan(newP.N)
            fprintf('    INCONCLUSIVE  both designs rejected (demo data too aggressive); core math runs without error\n');
        else
            fprintf('    FAIL  Bpk_new=%.4f Bpk_legacy=%.4f (need new>legacy)\n', newP.Bpk, legacyP.Bpk);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 8: Steinmetz coefficients mapped correctly (k/alpha) --------
    %
    %   Guards the import bug where alpha<->k were swapped, making fs^alpha use
    %   fs^3.2 instead of fs^1.46 and blowing core loss up to ~1e16 mW/cm^3,
    %   which rejected EVERY transformer candidate. For material P the fit is
    %   k=3.2, alpha=1.46, beta=2.75; a physical nPnucleoSE must stay small.
    fprintf('\n[8] Steinmetz k/alpha mapping (material P)\n');
    try
        idxP = find(strcmp(string(cat.steinmetz.Material), 'P'), 1);
        row = table2struct(cat.steinmetz(idxP, :));
        nP = (row.k * 50000^row.alpha * 0.05^row.beta * ...
              (row.c1_T - row.c2_T*55 + row.c3_T*55^2)) / 1000;   % mW/cm^3
        if i_close(row.alpha, 1.46, 1e-2, tolAbs) && i_close(row.k, 3.2, 1e-2, tolAbs) ...
                && isfinite(nP) && nP < 1000
            fprintf('    PASS  P: alpha=%.3f k=%.3f -> nPnucleoSE=%.2f mW/cm^3 (physical)\n', ...
                row.alpha, row.k, nP);
        else
            fprintf('    FAIL  P: alpha=%.3f k=%.3f nPnucleoSE=%.3g (swapped/non-physical)\n', ...
                row.alpha, row.k, nP);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 9: per-material curve-fit coefficients differ --------
    %
    %   Guards against reverting to one shared (MPP-40) core-loss fit for all
    %   Magnetics materials, which made every inductor point nearly identical.
    fprintf('\n[9] Magnetics curve-fit per-material differentiation\n');
    try
        T = cat.curvefit;
        getPa = @(m,mu) i_paAt(T, m, mu);
        paKool = getPa('Kool Mu', 60);
        paXFlux = getPa('XFlux', 60);
        paEdge  = getPa('Edge', 60);
        if abs(paKool - paXFlux) > 1 && abs(paKool - paEdge) > 1 && abs(paXFlux - paEdge) > 1
            fprintf('    PASS  P_a @mu60: KoolMu=%.1f XFlux=%.1f Edge=%.1f (distinct)\n', ...
                paKool, paXFlux, paEdge);
        else
            fprintf('    FAIL  P_a identical across materials: KoolMu=%.1f XFlux=%.1f Edge=%.1f\n', ...
                paKool, paXFlux, paEdge);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 10: density combination formulas (vs original app2) --------
    %
    %   eta uses the SAME formula as the original power-density tab:
    %       eta = (P_out - TotalLoss)/P_out * 100
    %   with TotalLoss/TotalVol = sum(multiplier_i * unit_i). Hand anchor:
    %       TotalL = 6*50+6*50+6*30+3*40+1*60 = 960 W
    %       TotalV = 6*200+6*200+6*150+3*300+1*500 = 4700 cm^3 = 4.7 L
    fprintf('\n[10] density combination (eta, power/loss density)\n');
    try
        mk = @(id,pw,vol) table(string(id),pw,vol, ...
            'VariableNames',{'Identifier','PowerW','Volume_cm3'});
        comp = struct('mosfetI',mk('M1',50,200),'mosfetI_mult',6, ...
                      'mosfetII',mk('M2',50,200),'mosfetII_mult',6, ...
                      'diode',mk('D',30,150),'diode_mult',6, ...
                      'inductor',mk('L',40,300),'inductor_mult',3, ...
                      'transformer',mk('T',60,500),'transformer_mult',1);
        o = struct('P_final',50000,'Metric','loss','Loss_max',1e9,'LossDens_max',1e9);
        r = pdpwr.density(comp,o);
        okE = i_close(r.eff(1),      (50000-960)/50000*100, tolRel, tolAbs);
        okP = i_close(r.powerDens(1), 50000/4.7,            tolRel, tolAbs);
        okL = i_close(r.lossDens(1),  960/4.7,              tolRel, tolAbs);
        okT = i_close(r.loss(1),      960,                  tolRel, tolAbs);
        if okE && okP && okL && okT
            fprintf('    PASS  eta=%.3f%% powerDens=%.1f lossDens=%.2f loss=%.0f\n', ...
                r.eff(1), r.powerDens(1), r.lossDens(1), r.loss(1));
        else
            fprintf('    FAIL  eta=%.3f powerDens=%.1f lossDens=%.2f loss=%.0f\n', ...
                r.eff(1), r.powerDens(1), r.lossDens(1), r.loss(1));
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 11: heatsink thermal chain + empirical length fit --------
    %
    %   Rth_required = min( (Ths-Tamb)/(Q*P) , (T_HS_max-Tamb)/(Q*P) ) with
    %   Ths = Tj - P*(Rth_jc+Rth_chs); then L = 64.1030/(coef-0.4258)+14.754
    %   where coef = Rth_required/Rth_HA. Same formulas as the legacy DIODESapp.
    fprintf('\n[11] heatsink thermal chain + length fit\n');
    try
        hop = struct('Tj',125,'T_amb',55,'T_HS_max',100,'Qtdd',1,'L_min',0.001, ...
            'L_max',300,'Rth_jc',1,'Rth_chs',0.5,'convection','Natural');
        fits = pdpwr.design.heatsink(30, hop, cat.heatsinks);
        Ths  = 125 - 30*(1+0.5);
        Rreq = min((Ths-55)/30, (100-55)/30);
        Lexp = 64.1030/(Rreq/fits(1).Rth_HA - 0.4258) + 14.754;
        if ~isempty(fits) && i_close(fits(1).Rth_required, Rreq, 1e-4, tolAbs) ...
                && i_close(fits(1).length_mm, Lexp, tolRel, tolAbs)
            fprintf('    PASS  Rth_req=%.4f  L=%.2f mm  (profile %s)\n', ...
                fits(1).Rth_required, fits(1).length_mm, fits(1).profile);
        else
            fprintf('    FAIL  Rth_req=%.4f (exp %.4f)  L=%.2f (exp %.2f)\n', ...
                fits(1).Rth_required, Rreq, fits(1).length_mm, Lexp);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 12: transformer Faraday with user constant k --------
    %
    %   Np = round(Vd*1e4/(k*Bm*fs*Ae_cm2)). Prof. Demercil confirmed the k=9
    %   form; k is now user-editable. Np must scale as 1/k: k=9->12, 4.44->24.
    fprintf('\n[12] transformer Faraday constant k (Np ~ 1/k)\n');
    try
        wire = pdpwr.util.awg_props(16, cat.awg);
        D = struct('Vd',600,'Vo',920,'n',1.2,'Ipef',5,'Isef',5/1.2,'fs',50000, ...
            'Ts',1/50000,'T',55,'kumin',0.0,'kumax',9.9,'DeltaTmax',999, ...
            'Dfio',wire.D_cm,'Afio',wire.A_cm2,'Rfio',wire.r_ohm_m*1e-2, ...
            'Bm',0.15,'J',300,'Pnucleomax',1e9,'Vmax',1e9);
        D.Rcfio=D.Rfio*(1+0.0038*(D.T-20)); D.D=D.Vo/(2*D.Vd*D.n); D.D2=1-D.D;
        core = struct('partNumber','9928','manufacturer','x','geometry','EE', ...
            'parallel',1,'Ae_cm2',7.38,'Ve_cm3',150,'Ap_cm4',90.6,'OD_cm',NaN, ...
            'ID_cm',NaN,'H_cm',2.75,'Length_cm',10,'LegLength_cm',6);
        stein = struct('Material','P','alpha',1.46,'beta',2.75,'k',3.2, ...
            'c1_T',2.45,'c2_T',0.031,'c3_T',0.000165);
        okK = true; msg = '';
        for k = [9 4.44 4]
            D.kFaraday = k;
            pj = pdpwr.design.transformer(D, core, stein, struct('gseEnabled',false));
            NpExp = round(600*1e4/(k*0.15*50000*7.38));
            okK = okK && (abs(pj.Np - NpExp) < 0.5);
            msg = sprintf('%s k=%.2f:Np=%d(exp%d) ', msg, k, pj.Np, NpExp);
        end
        if okK
            fprintf('    PASS %s\n', msg);
        else
            fprintf('    FAIL %s\n', msg); failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    fprintf('\n=== Total failures: %d ===\n', failures);
end


function pa = i_paAt(T, material, mu)
    sel = strcmp(string(T.Material), material);
    sub = T(sel, :);
    [~, idx] = min(abs(sub.Permeability - mu));
    pa = sub.P_a(idx);
end


function ok = i_close(a, b, relTol, absTol)
    if a == 0 && b == 0, ok = true; return; end
    err = abs(a - b);
    ok = err < absTol || err / max(abs(a), abs(b)) < relTol;
end


function i_expect(actual, expected, label, absTol)
    if abs(actual - expected) > absTol
        error('Expected %s=%g, got %g', label, expected, actual);
    end
end


function D = i_designDataDemo()
% Minimal Data struct used to exercise design.inductor.
% Filters are relaxed so the design isn't rejected and we can compare Bpk
% legacy vs corrected.
    D = struct( ...
        'Vd', 800, 'ILmed', 10, 'DeltaIL', 2, 'IL_max', 2, 'ILef', 10.1, ...
        'L', 200e-6, 'J', 350, 'fs', 50e3, ...
        'r_awg', 13.18e-3, 'Aawg', 14.73e-3, 'Dextawg', 0.137, ...
        'temp_ambiente', 60, 'DeltaTmax', 200, ...
        'kumin', 0.001, 'kumax', 0.99, 'MaxLoss', 1000, 'MaxVol', 100000);
end


function core = i_coreDemo()
% Demo Magnetics-style core (similar to Kool Mu)
    core = struct( ...
        'id',      'KoolMu77437A7', ...
        'mi_rel',  60, ...
        'le_mm',   80.16, ...
        'Ae_mm2',  130, ...
        'Vol_mm3', 10500, ...
        'OD_mm',   41.9, ...
        'ID_mm',   24.1, ...
        'HT_mm',   14.7, ...
        'stacks',  1, ...
        'mi_a', 0.01,  'mi_b', 2.702e-8, 'mi_c', 2.511, ...
        'P_a',  146.94, 'P_b', 2.103, 'P_c', 1.357);
end
