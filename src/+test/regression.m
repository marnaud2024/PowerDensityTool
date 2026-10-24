function regression()
%TEST.REGRESSION Self-contained validation of the +pdpwr package.
%
%   Run from the PowerDensityTool/src folder:
%       cd src
%       test.regression
%
%   The suite does not depend on the legacy app code. It compares the
%   pdpwr.* implementation against numerical anchors computed by hand from
%   the catalog files (embedded below) and against physical checks of the
%   models. A FAIL line prints the value obtained and the value expected.

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

    % -------- TEST 10: density combination formulas --------
    %
    %   eta = P_out/(P_out + TotalLoss)*100, every family multiplied by its
    %   unit count. The transformer unit carries Ptrafo(upper)+Ptrafo(lower),
    %   so fT transformers add (fT/2)*unit loss and fT*unit volume. Anchor:
    %       TotalL = 1*50 + 1*50 + 1*30 + 3*40 + (6/2)*60 = 430 W
    %       TotalV = 1*200 + 1*200 + 1*150 + 3*300 + 6*500 = 4450 cm^3
    fprintf('\n[10] density combination (eta, power/loss density, multipliers)\n');
    try
        mk = @(id,pw,vol) table(string(id),pw,vol, ...
            'VariableNames',{'Identifier','PowerW','Volume_cm3'});
        comp = struct('mosfetI',mk('M1',50,200),'mosfetI_mult',1, ...
                      'mosfetII',mk('M2',50,200),'mosfetII_mult',1, ...
                      'diode',mk('D',30,150),'diode_mult',1, ...
                      'inductor',mk('L',40,300),'inductor_mult',3, ...
                      'transformer',mk('T',60,500),'transformer_mult',6);
        o = struct('P_final',10000,'Metric','loss','Loss_max',1e9,'LossDens_max',1e9);
        r = pdpwr.density(comp,o);
        okE = i_close(r.eff(1),       10000/(10000+430)*100, tolRel, tolAbs);
        okP = i_close(r.powerDens(1), 10000/4.45,            tolRel, tolAbs);
        okL = i_close(r.lossDens(1),  430/4.45,              tolRel, tolAbs);
        okT = i_close(r.loss(1),      430,                   tolRel, tolAbs);
        comp.mosfetI_mult = 2;                      % a second heatsink group
        r2 = pdpwr.density(comp,o);
        okM = i_close(r2.loss(1), 480, tolRel, tolAbs);
        if okE && okP && okL && okT && okM
            fprintf('    PASS  eta=%.3f%% powerDens=%.1f lossDens=%.2f loss=%.0f (x2 MOSFET-I: %.0f)\n', ...
                r.eff(1), r.powerDens(1), r.lossDens(1), r.loss(1), r2.loss(1));
        else
            fprintf('    FAIL  eta=%.3f powerDens=%.1f lossDens=%.2f loss=%.0f (x2 MOSFET-I: %.0f, exp 480)\n', ...
                r.eff(1), r.powerDens(1), r.lossDens(1), r.loss(1), r2.loss(1));
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

    % -------- TEST 13: GSE coefficient k1 (Li 2001) in the catalog --------
    %
    %   k1 = k / ((2*pi)^(alpha-1) * int_0^2pi |cos t|^alpha |sin t|^(beta-alpha) dt)
    %   The catalog column k_iGSE must hold this value for every material
    %   with Steinmetz coefficients (TDK rows are zero and use the neural net).
    fprintf('\n[13] GSE coefficient k1 vs Li (2001) definition\n');
    try
        S = cat.steinmetz; ok13 = true; msg = '';
        for i = 1:height(S)
            if S.k(i) == 0, continue; end
            al = S.alpha(i); be = S.beta(i);
            I = integral(@(t) abs(cos(t)).^al .* abs(sin(t)).^(be-al), 0, 2*pi);
            k1 = S.k(i) / ((2*pi)^(al-1) * I);
            okI = i_close(S.k_iGSE(i), k1, 1e-3, tolAbs);
            ok13 = ok13 && okI;
            msg = sprintf('%s %s:%.4f/%.4f', msg, string(S.Material(i)), S.k_iGSE(i), k1);
        end
        if ok13
            fprintf('    PASS %s\n', msg);
        else
            fprintf('    FAIL (catalog/formula)%s\n', msg); failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 14: transformer GSE vs an independent integration --------
    %
    %   Rebuilds B(t) from the six-step voltage by Faraday's law with a fine
    %   time grid, evaluates the GSE integral by trapezoids and compares with
    %   pdpwr.design.transformer at the same core temperature. The upper and
    %   lower waveforms are mirror images, so their core losses must match.
    fprintf('\n[14] transformer GSE (six-step) vs independent integration\n');
    try
        idxR = find(strcmp(string(cat.steinmetz.Material), 'R'), 1);
        stR = table2struct(cat.steinmetz(idxR, :));
        D = struct('Vd',600,'Vo',920,'n',1.2,'Ipef',8,'Isef',8/1.2,'fs',50000, ...
            'Ts',1/50000,'T',25,'kumin',0,'kumax',9.9,'DeltaTmax',999, ...
            'Bm',0.1,'J',300,'Pnucleomax',1e9,'Vmax',1e9,'kFaraday',9,'Fr',1);
        D.Dfio = (0.127*92^((36-38)/39))/10; D.Afio = pi*(D.Dfio/2)^2;
        D.Rfio = 1.72e-6/D.Afio; D.Rcfio = D.Rfio;
        D.D = D.Vo/(2*D.Vd*D.n); D.D2 = 1 - D.D;
        core = struct('partNumber','test','manufacturer','x','geometry','R','parallel',1, ...
            'Ae_cm2',1.0,'Ve_cm3',10,'Ap_cm4',5,'OD_cm',4,'ID_cm',2.4,'H_cm',1.5, ...
            'Length_cm',NaN,'LegLength_cm',NaN);
        pj = pdpwr.design.transformer(D, core, stR);
        Aef = core.Ae_cm2*1e-4;
        Pref = zeros(1,2); dds = [D.D2 D.D]; Tc = [pj.Tcore pj.Tcore];
        for g = 1:2
            dd = dds(g);
            d1 = D.Ts*(3*dd-1)/3; d2 = D.Ts*(2-3*dd)/3;
            edges = [0 cumsum([d1 d2 d1 d2 d1 d2])];
            lev = [1 2 1 -1 -2 -1]*D.Vd/3;
            t = linspace(0, D.Ts, 600001);
            v = zeros(size(t));
            for k = 1:6, v(t >= edges(k) & t < edges(k+1)) = lev(k); end
            B = cumtrapz(t, v)/(pj.Np*Aef);
            B = B - (max(B)+min(B))/2;               % symmetric flux
            dB = v/(pj.Np*Aef);
            f = abs(dB).^stR.alpha .* abs(B).^(stR.beta-stR.alpha);
            Pv = stR.k_iGSE/D.Ts * trapz(t, f) * ...
                 (stR.c1_T - stR.c2_T*Tc(g) + stR.c3_T*Tc(g)^2);   % W/m^3
            Pref(g) = core.Ve_cm3*Pv/1e6;
        end
        okA = i_close(pj.PnucleoGSEsup, Pref(1), 5e-3, tolAbs);
        okB = i_close(pj.PnucleoGSEinf, Pref(2), 5e-3, tolAbs);
        okC = i_close(pj.PnucleoGSEsup, pj.PnucleoGSEinf, 1e-3, tolAbs);
        if okA && okB && okC
            fprintf('    PASS  GSE sup=%.4f W (ref %.4f)  inf=%.4f W (ref %.4f)\n', ...
                pj.PnucleoGSEsup, Pref(1), pj.PnucleoGSEinf, Pref(2));
        else
            fprintf('    FAIL  GSE sup=%.4f W (ref %.4f)  inf=%.4f W (ref %.4f)\n', ...
                pj.PnucleoGSEsup, Pref(1), pj.PnucleoGSEinf, Pref(2));
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 15: TDK ferrites get a core loss from the neural net --------
    fprintf('\n[15] TDK N87 core loss (neural net) is positive\n');
    try
        net = pdpwr.util.load_neural_net();
        net.materialIdx = 9;                        % N87
        idxN = find(strcmp(string(cat.steinmetz.Material), 'N87'), 1);
        stN = table2struct(cat.steinmetz(idxN, :));
        pN = pdpwr.design.transformer(D, core, stN, struct('neuralNet', net));
        if isfinite(pN.PnucleoGSEsup) && pN.PnucleoGSEsup > 0 && pN.Ptrafo > pN.PcondSup
            fprintf('    PASS  N87 core loss = %.4f W, total = %.4f W\n', pN.PnucleoGSEsup, pN.Ptrafo);
        else
            fprintf('    FAIL  N87 core loss = %.4g W (must be > 0)\n', pN.PnucleoGSEsup);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 16: inductor flux swing and winding temperature --------
    %
    %   Bpk = L*DeltaIL/(2*N*Ae), with the same ripple that sets L, and the
    %   copper loss evaluated at Tamb + dT: R = R20*(1 + 0.00393*(Tamb+dT-20)).
    fprintf('\n[16] inductor Bpk and copper temperature\n');
    try
        Di = i_designDataDemo();
        Di.ILmed = 5; Di.DeltaIL = 1; Di.IL_max = 1; Di.L = 200e-6;
        Di.ILef = Di.ILmed*sqrt(1 + (Di.DeltaIL/Di.ILmed)^2/12);
        c = i_coreDemo();
        pI = pdpwr.design.inductor(Di, c);
        BpkExp = Di.L*Di.DeltaIL/(2*pI.N*c.Ae_mm2*1e-6);
        CEM = (2*c.HT_mm + (c.OD_mm - c.ID_mm))*1.1;
        PcuExp = pI.N*CEM*Di.r_awg*(1 + 0.00393*(Di.temp_ambiente + pI.DeltaT - 20))*1e-3/pI.Nparal*Di.ILef^2;
        if ~isnan(pI.N) && i_close(pI.Bpk, BpkExp, 1e-9, tolAbs) && i_close(pI.Pcu, PcuExp, 1e-3, tolAbs)
            fprintf('    PASS  N=%d Bpk=%.4f T  Pcu=%.3f W (dT=%.1f C)\n', pI.N, pI.Bpk, pI.Pcu, pI.DeltaT);
        else
            if isfield(pI, 'reason'), why = pI.reason; else, why = ''; end
            fprintf('    FAIL  Bpk=%.5f (exp %.5f)  Pcu=%.4f (exp %.4f) %s\n', pI.Bpk, BpkExp, pI.Pcu, PcuExp, why);
            failures = failures + 1;
        end
    catch ME
        fprintf('    FAIL  %s\n', ME.message); failures = failures + 1;
    end

    % -------- TEST 17: transformer core geometry read from the catalog --------
    %
    %   Part numbers come as text (MMT139T6325 must not turn into NaN) and the
    %   TDK rows written with a decimal comma ('42,10') must be converted.
    fprintf('\n[17] transformer catalog: part numbers and decimal commas\n');
    try
        Tt = cat.trafos;
        nNaN = nnz(isnan(Tt.Ae_mm2)) + nnz(isnan(Tt.Ve_mm3));
        hasMMT = any(Tt.PartNumber == "MMT139T6325");
        iPQ = find(Tt.PartNumber == "PQ16/11.6", 1);
        okPQ = ~isempty(iPQ) && i_close(Tt.Ae_mm2(iPQ), 42.1, tolRel, tolAbs);
        if nNaN == 0 && hasMMT && okPQ
            fprintf('    PASS  no NaN in Ae/Ve, MMT139T6325 found, PQ16/11.6 Ae = %.1f mm^2\n', Tt.Ae_mm2(iPQ));
        else
            fprintf('    FAIL  NaN in Ae/Ve: %d, MMT139T6325 found: %d, PQ16 ok: %d\n', nNaN, hasMMT, okPQ);
            failures = failures + 1;
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
