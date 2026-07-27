function ctx = tab_density(app)
%TAB_DENSITY Power density combination tab.

    L = pdpwr.ui.layout();
    tab = uitab(app.TabGroup, 'Title', 'Power Density');
    ctx.tab = tab;

    panel = uipanel(tab, 'Title', 'Combination Parameters', 'FontWeight','bold', ...
        'Position', [L.inputPanel.x L.inputPanel.y L.inputPanel.w L.inputPanel.h]);
    rows = i_fieldList();
    ctx.spinners = struct();
    yTop = L.inputPanel.h - 30;
    for k = 1:numel(rows)
        f = rows(k);
        y = yTop - k * (L.spinnerRowHeight + L.spinnerRowSpacing);
        s = pdpwr.ui.spinner_row(panel, 10, y, f.label, f.default, ...
            'Limits', f.limits, 'Step', f.step);
        ctx.spinners.(f.name) = s;
    end
    yLast = yTop - (numel(rows)+1) * (L.spinnerRowHeight + L.spinnerRowSpacing);

    % Metric dropdown - selects which analysis view (and which spinner pair)
    uilabel(panel, 'Position', [10, yLast, 200, L.spinnerRowHeight], ...
        'Text', 'Analysis view:', 'HorizontalAlignment','right', 'FontWeight','bold');
    ctx.metricDropdown = uidropdown(panel, ...
        'Position', [216, yLast, 150, L.spinnerRowHeight], ...
        'Items', {'Loss / Vol', 'P_out / Vol'}, ...
        'Value', 'Loss / Vol');   % default reproduces the original app2 graph

    % How many combinations to evaluate/plot
    yCombo = yLast - (L.spinnerRowHeight + L.spinnerRowSpacing);
    uilabel(panel, 'Position', [10, yCombo, 200, L.spinnerRowHeight], ...
        'Text', 'Combinations:', 'HorizontalAlignment','right', 'FontWeight','bold');
    ctx.comboDropdown = uidropdown(panel, ...
        'Position', [216, yCombo, 150, L.spinnerRowHeight], ...
        'Items', {'Spread (fast)', 'Top 10 best', 'All (slow)'}, ...
        'Value', 'Spread (fast)');

    % Tutorial - tall enough to avoid a scroll bar
    tutH = 268;
    tutY = max(12, yCombo - L.spinnerRowHeight - tutH);
    uilabel(panel, 'Position', [10, tutY+tutH, 360, 18], ...
        'Text', 'How to use the Power Density tab', ...
        'FontWeight','bold', 'FontColor',[0.2 0.4 0.7]);
    uitextarea(panel, 'Position', [10, tutY, 360, tutH], ...
        'Editable', 'off', 'WordWrap', 'on', 'FontSize', 10, ...
        'Value', { ...
            '1. Run all 5 upstream tabs first (MOSFET-I, MOSFET-II, Diode, Inductor, Transformer), then click Refresh on the right.', ...
            '2. Multipliers = how many UNITS (arms) of each component the converter uses. A semiconductor unit is one heatsink plus its Devices-per-HS dies (the unit loss is the whole group); a magnetics unit is one core design.', ...
            '3. Analysis view (the unused filter pair greys out): "Loss / Vol" (default) plots Efficiency x Loss density - the same graph as the original tool - and filters by Max Total Losses + Max Loss Density. "P_out / Vol" plots Efficiency x Power density and filters by Min Efficiency + Min Power Density. In both, efficiency = (P_out - losses)/P_out.', ...
            '4. Combinations: "Spread" (default) samples 10 entries per family across the loss range - keeps the full cloud and is fast. "Top 10 best" uses the 10 lowest-loss. "All" combines every cached design to locate a specific one (slow, high memory - asks for confirmation).', ...
            '5. Click Calculate to draw the chart and write output/.'});

    % Cached results status (right column, replacing the trees area)
    ctx.statusPanel = uipanel(tab, 'Title', 'Cached results from upstream tabs', ...
        'FontWeight','bold', 'Title', 'Cached counts  /  selected combination', ...
        'Position', [L.treeWide.x L.treeWide.y L.treeWide.w L.treeWide.h]);
    pw = L.treeWide.w - 20;
    ctx.statusText = uitextarea(ctx.statusPanel, ...
        'Position', [10 312 pw 100], ...
        'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
    uilabel(ctx.statusPanel, 'Position', [10 288 pw 18], ...
        'Text', 'Selected combination (click a table row):', ...
        'FontWeight','bold', 'FontColor',[0.2 0.4 0.7]);
    ctx.detailText = uitextarea(ctx.statusPanel, ...
        'Position', [10 40 pw 244], ...
        'Editable', 'off', 'WordWrap', 'on', 'FontName', 'Consolas', 'FontSize', 11, ...
        'Value', {'Click a row in the results table below to see all the', ...
                  'constructive details of that combination here.'});
    ctx.refreshButton = uibutton(ctx.statusPanel, 'push', ...
        'Position', [10 8 140 26], ...
        'Text', 'Refresh cached counts');

    uilabel(tab, 'Position', [L.treeWideLabel.x L.treeWideLabel.y L.treeWideLabel.w L.treeWideLabel.h], ...
        'Text', 'Cached counts + full details of the selected combination', ...
        'FontWeight', 'bold', 'FontSize', 11);

    % Plot
    ctx.ax = uiaxes(tab, 'Position', [L.plot.x L.plot.y L.plot.w L.plot.h]);
    title(ctx.ax, 'Efficiency x Power Density');
    xlabel(ctx.ax, 'Efficiency [%]'); ylabel(ctx.ax, 'Density [W/L]');
    grid(ctx.ax, 'on');

    % Buttons + status (callbacks assigned at the END)
    ctx.calcButton = uibutton(tab, 'push', ...
        'Position', [L.calcButton.x L.calcButton.y L.calcButton.w L.calcButton.h], ...
        'Text', 'Calculate');
    ctx.openButton = uibutton(tab, 'push', ...
        'Position', [L.graphButton.x L.graphButton.y L.graphButton.w L.graphButton.h], ...
        'Text', 'Open results folder');
    ctx.statusLabel = uilabel(tab, ...
        'Position', [L.statusLabel.x L.statusLabel.y L.statusLabel.w L.statusLabel.h], ...
        'Text', 'Status: Idle');

    ctx.tableCols = {'#','Eff [%]','PowerDens [W/L]','Loss [W]','LossDens [W/L]', ...
                     'MOSFET-I','MOSFET-II','Diode','Inductor','Transformer'};
    % Cells hold SHORT labels (full build details show in the panel on the right
    % when a row is clicked), so the columns stay readable.
    ctx.table = uitable(tab, ...
        'Position', [L.table.x L.table.y L.table.w L.table.h], ...
        'ColumnName', ctx.tableCols, ...
        'ColumnWidth', {32,54,92,74,82,170,170,150,160,170}, ...
        'Data', cell(0, numel(ctx.tableCols)));

    % ctx complete - assign callbacks now.
    ctx.calcButton.ButtonPushedFcn    = @(~,~) i_on_calculate(app, ctx);
    ctx.openButton.ButtonPushedFcn    = @(~,~) i_open_folder(app);
    ctx.refreshButton.ButtonPushedFcn = @(~,~) i_refresh_status(app, ctx);
    ctx.metricDropdown.ValueChangedFcn = @(~,~) i_apply_mode(ctx);
    ctx.table.CellSelectionCallback   = @(~,evt) i_on_select(app, ctx, evt);

    i_apply_mode(ctx);       % set initial enabled pair + axis labels
    i_refresh_status(app, ctx);
end


function i_apply_mode(ctx)
% Enable the spinner pair that matches the chosen view and relabel the axes.
    isLoss = startsWith(ctx.metricDropdown.Value, 'Loss');
    effPair  = {'etaMin','densMin'};
    lossPair = {'lossMax','lossDensMax'};
    for k = 1:numel(effPair),  ctx.spinners.(effPair{k}).Enable  = i_onoff(~isLoss); end
    for k = 1:numel(lossPair), ctx.spinners.(lossPair{k}).Enable = i_onoff(isLoss);  end
    cla(ctx.ax);
    ctx.table.Data = cell(0, numel(ctx.tableCols));
    % X = Efficiency, Y = Density (same orientation as the original app2).
    if isLoss
        title(ctx.ax, 'Efficiency x Loss density');
        xlabel(ctx.ax, 'Efficiency [%]'); ylabel(ctx.ax, 'Loss Density [W/L]');
    else
        title(ctx.ax, 'Efficiency x Power density');
        xlabel(ctx.ax, 'Efficiency [%]'); ylabel(ctx.ax, 'Power Density [W/L]');
    end
    grid(ctx.ax, 'on');
end


function s = i_onoff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end


function f = i_fieldList()
    % etaMin/densMin form the EFFICIENCY pair (mode 'P_out / Vol');
    % lossMax/lossDensMax form the LOSSES pair (mode 'Loss / Vol'). One pair is
    % enabled at a time depending on the metric dropdown.
    f = struct( ...
        'name', {'P_out','fM1','fM2','fD','fL','fT','etaMin','densMin','lossMax','lossDensMax'}, ...
        'label',{'Output Power (W)','MOSFET-I multiplier','MOSFET-II multiplier', ...
                 'Diode multiplier','Inductor multiplier','Transformer multiplier', ...
                 'Min Efficiency (%)','Min Power Density (W/L)', ...
                 'Max Total Losses (W)','Max Loss Density (W/L)'}, ...
        'default',{50000, 6, 6, 6, 3, 1, 90, 0, 1e5, 1e6}, ...
        'limits', {[100 1e6],[1 100],[1 100],[1 100],[1 100],[1 100],[0 100],[0 1e6],[0 1e6],[0 1e7]}, ...
        'step',   {1000, 1, 1, 1, 1, 1, 1, 100, 100, 100});
end


function i_refresh_status(app, ctx)
    c = [ i_count(app,'mosfetI','hsAll'), ...
          i_count(app,'mosfetII','hsAll'), ...
          i_count(app,'diode','hsAll'), ...
          i_count(app,'inductor','records'), ...
          i_count(app,'transformer','records') ];
    lines = {
        sprintf('MOSFET-I       : %6d records', c(1)), ...
        sprintf('MOSFET-II      : %6d records', c(2)), ...
        sprintf('Diode          : %6d records', c(3)), ...
        sprintf('Inductor       : %6d records', c(4)), ...
        sprintf('Transformer    : %6d records', c(5)), ...
        ''};
    if min(c) == 0
        lines{end+1} = '** Run each upstream tab, then click Refresh. **';
    else
        lines{end+1} = 'All tabs have results.';
        lines{end+1} = 'Each family is sampled to a spread of 10';
        lines{end+1} = 'entries when combining (10^5 = 100k sets).';
        lines{end+1} = 'Click Calculate below.';
    end
    ctx.statusText.Value = lines;
end


function n = i_count(app, key, field)
    r = app.get_results(key);
    if isempty(r) || ~isfield(r,field), n = 0; return; end
    n = numel(r.(field));
end


function i_open_folder(app)
% Open the folder where every tab saves its .xlsx / .csv results, so the user
% can take the data to Excel, LibreOffice, Python, etc.
    d = pdpwr.util.output_dir();
    ok = false;
    try
        if ispc,        winopen(d);                 ok = true;
        elseif ismac,   system(['open "' d '" &']); ok = true;
        else,           system(['xdg-open "' d '" &']); ok = true;
        end
    catch
    end
    if ~ok
        uialert(app.UIFigure, sprintf('Results (xlsx + csv) are saved in:\n%s', d), ...
            'Results folder', 'Icon', 'info');
    end
end


function i_on_calculate(app, ctx)
    ctx.calcButton.Enable = 'off';
    ctx.statusLabel.Text = 'Status: Loading cached results...';
    pd = uiprogressdlg(app.UIFigure, 'Title','Power Density', ...
        'Message','Loading...', 'Indeterminate','off');

    try
        m1 = app.get_results('mosfetI');
        m2 = app.get_results('mosfetII');
        d  = app.get_results('diode');
        l  = app.get_results('inductor');
        t  = app.get_results('transformer');
        missing = {};
        if isempty(m1), missing{end+1} = 'MOSFET-I';    end
        if isempty(m2), missing{end+1} = 'MOSFET-II';   end
        if isempty(d),  missing{end+1} = 'Diode';       end
        if isempty(l),  missing{end+1} = 'Inductor';    end
        if isempty(t),  missing{end+1} = 'Transformer'; end
        if ~isempty(missing)
            uialert(app.UIFigure, ['Run first: ', strjoin(missing, ', ')], 'Missing data');
            try, close(pd); catch, end; try, ctx.calcButton.Enable='on'; catch, end; return
        end

        s = ctx.spinners;
        opts = struct('P_final', s.P_out.Value);
        if startsWith(ctx.metricDropdown.Value, 'Loss')
            opts.Metric = 'loss';
            opts.Loss_max     = s.lossMax.Value;
            opts.LossDens_max = s.lossDensMax.Value;
        else
            opts.Metric = 'output';
            opts.Eff_min  = s.etaMin.Value;
            opts.Dens_min = s.densMin.Value;
        end

        % How many combinations: a representative SPREAD per family (default,
        % keeps the full trade-off cloud cheaply), the TOP-10 lowest-loss, or
        % ALL records (find any specific design, even a bad one - slow/heavy).
        % A semiconductor "unit" = ONE heatsink carrying its Devices-per-HS dies,
        % so the unit loss is the GROUP loss (Q x single-die loss).
        switch ctx.comboDropdown.Value
            case 'All (slow)',  capMode = 'all';    CAP = inf; opts.MaxResults = 1e6;
            case 'Top 10 best', capMode = 'top';    CAP = 10;  opts.MaxResults = inf;
            otherwise,          capMode = 'spread'; CAP = 10;  opts.MaxResults = inf;
        end

        comp = struct();
        comp.mosfetI         = i_capByLoss(i_toTable(m1.hsAll, 'GroupLossW','Volume_cm3','semi'), CAP, capMode);
        comp.mosfetI_mult    = s.fM1.Value;
        comp.mosfetII        = i_capByLoss(i_toTable(m2.hsAll, 'GroupLossW','Volume_cm3','semi'), CAP, capMode);
        comp.mosfetII_mult   = s.fM2.Value;
        comp.diode           = i_capByLoss(i_toTable(d.hsAll, 'GroupLossW','Volume_cm3','semi'), CAP, capMode);
        comp.diode_mult      = s.fD.Value;
        comp.inductor        = i_capByLoss(i_toTable(l.records, 'Ptotal','Vol','inductor'), CAP, capMode);
        comp.inductor_mult   = s.fL.Value;
        comp.transformer     = i_capByLoss(i_toTable(t.records, 'Ptrafo','VolTotal','transformer'), CAP, capMode);
        comp.transformer_mult= s.fT.Value;

        nCombo = height(comp.mosfetI)*height(comp.mosfetII)*height(comp.diode)* ...
                 height(comp.inductor)*height(comp.transformer);

        if strcmp(capMode, 'all')
            sel = uiconfirm(app.UIFigure, sprintf([ ...
                '"All" combines every cached design: up to %.3g sets, storing the\n' ...
                'first %g that pass the filters. This can take a while and use a lot\n' ...
                'of memory. Tip: filter each upstream tab first to shrink the lists.\n\nContinue?'], ...
                nCombo, opts.MaxResults), 'Heavy combination', ...
                'Options',{'Continue','Cancel'}, 'DefaultOption','Cancel');
            if strcmp(sel,'Cancel')
                try, close(pd); catch, end; try, ctx.calcButton.Enable='on'; catch, end; return
            end
        end

        ctx.statusLabel.Text = sprintf('Status: Combining up to %.3g (metric: %s, %s)...', nCombo, opts.Metric, capMode);
        pd.Value = 0.3; pd.Message = sprintf('Combining up to %.3g candidate sets...', nCombo);
        res = pdpwr.density(comp, opts);

        if isempty(res.eff)
            % Clear the chart and table so the empty result is explicit.
            i_apply_mode(ctx);
            if strcmpi(opts.Metric, 'loss')
                hint = 'Raise Max Total Losses / Max Loss Density, or check the multipliers.';
            else
                hint = 'Lower Min Efficiency / Min Power Density, or check the multipliers.';
            end
            ctx.statusLabel.Text = ['Status: 0 combinations passed - ' hint];
            uialert(app.UIFigure, ['No combination satisfied the filters.' newline hint], 'No results');
            try, close(pd); catch, end; try, ctx.calcButton.Enable='on'; catch, end; return
        end

        try, pd.Value=0.85; pd.Message='Drawing chart...'; catch, end
        app.set_results('densityLast', res);   % for the row-click detail panel
        i_drawScatter(ctx.ax, res);
        i_fillTable(ctx, res);
        ctx.detailText.Value = {'Click a row in the results table below to see all the', ...
                                'constructive details of that combination here.'};

        folder = pdpwr.util.save_table(i_toXlsxTable(res), 'power_density_results');
        ctx.statusLabel.Text = sprintf('Status: %d combos (%s) - saved xlsx+csv to %s', ...
            numel(res.eff), opts.Metric, folder);
        try, pd.Value=1.0; catch, end
        pause(0.1);
    catch ME
        try, uialert(app.UIFigure, ME.message, 'Density failed'); catch, end
        try, ctx.statusLabel.Text = sprintf('Error: %s', ME.message); catch, end
    end
    try, close(pd); catch, end
    try, ctx.calcButton.Enable='on'; catch, end
end


function i_drawScatter(ax, res)
    cla(ax); hold(ax, 'on');
    isLoss = strcmpi(res.metric, 'loss');
    % X = Efficiency (same orientation as the original app2). Y differs by view:
    %   Loss / Vol -> loss density (TotalL/Vol)  = exactly the legacy graph.
    %   P_out / Vol -> power density (P_out/Vol)  = the alternative.
    if isLoss
        x = res.eff; y = res.lossDens;
        xLab = 'Efficiency [%]'; yLab = 'Loss Density [W/L]';
        ttl  = sprintf('Efficiency x Loss density (%d combinations)', numel(x));
    else
        x = res.eff; y = res.powerDens;
        xLab = 'Efficiency [%]'; yLab = 'Power Density [W/L]';
        ttl  = sprintf('Efficiency x Power density (%d combinations)', numel(x));
    end
    p = plot(ax, x, y, 'bo');
    grid(ax, 'on'); title(ax, ttl); xlabel(ax, xLab); ylabel(ax, yLab);
    p.DataTipTemplate.DataTipRows(1).Label = xLab;   % = Efficiency [%]
    p.DataTipTemplate.DataTipRows(2).Label = yLab;   % = the density being viewed
    % Clean datatip: the axes already show efficiency + one density, so add only
    % the COMBO NUMBER, the total loss and the OTHER density (no duplicates). The
    % full constructive detail is in the table row of the same number.
    if isLoss
        otherDens = dataTipTextRow('Power Dens [W/L]', res.powerDens);
    else
        otherDens = dataTipTextRow('Loss Dens [W/L]', res.lossDens);
    end
    extra = [ ...
        dataTipTextRow('Combo #',  (1:numel(x))'); ...
        dataTipTextRow('Loss [W]', res.loss); ...
        otherDens ];
    p.DataTipTemplate.DataTipRows(end+1:end+numel(extra)) = extra;
    hold(ax, 'off');
end


function i_fillTable(ctx, res)
    n = numel(res.eff);
    data = cell(n, numel(ctx.tableCols));
    for i = 1:n
        det = res.detail(i);
        % First column = combo NUMBER (matches the "Combo #" in the chart datatip).
        % Component columns hold a SHORT label; the FULL constructive detail
        % appears in the side panel when the row is clicked (i_on_select).
        data(i,:) = {i, res.eff(i), res.powerDens(i), res.loss(i), res.lossDens(i), ...
                     i_shortLabel(det.M1), i_shortLabel(det.M2), ...
                     i_shortLabel(det.D), i_shortLabel(det.L), i_shortLabel(det.T)};
    end
    ctx.table.Data = data;
end


function s = i_shortLabel(v)
% First segment of a rich component label (everything before the first " | "),
% e.g. "6x G3R40MT12K [GeneSiC, TO-247-4]". Keeps the table cells readable.
    s = i_asChar(v);
    p = strfind(s, ' | ');
    if ~isempty(p), s = s(1:p(1)-1); end
end


function i_on_select(app, ctx, evt)
% Show the FULL constructive details of the clicked combination in the side
% panel (the table cell only shows a short label).
    if isempty(evt) || isempty(evt.Indices), return; end
    row = evt.Indices(1);
    res = [];
    try, res = app.get_results('densityLast'); catch, return; end
    if isempty(res) || ~isfield(res,'detail') || row > numel(res.detail), return; end
    d = res.detail(row);
    ctx.detailText.Value = { ...
        sprintf('COMBO #%d', row), ...
        sprintf('Eff=%.3f %%   PowerDens=%.1f W/L   Loss=%.1f W   LossDens=%.2f W/L', ...
                res.eff(row), res.powerDens(row), res.loss(row), res.lossDens(row)), ...
        '', ...
        'MOSFET-I:',    ['  ' i_asChar(d.M1)], ...
        'MOSFET-II:',   ['  ' i_asChar(d.M2)], ...
        'Diode:',       ['  ' i_asChar(d.D)], ...
        'Inductor:',    ['  ' i_asChar(d.L)], ...
        'Transformer:', ['  ' i_asChar(d.T)] };
end


function T = i_toXlsxTable(res)
% Export the BEST combinations first, capped so the spreadsheet stays usable.
% (All 100k+ combos with the long labels would make a 60+ MB file; the top set
% sorted by the objective is what a user actually wants.)
    EXPORT_CAP = 50000;
    if strcmpi(res.metric, 'loss')
        [~, ord] = sort(res.lossDens, 'ascend');    % best = low loss density
    else
        [~, ord] = sort(res.powerDens, 'descend');  % best = high power density
    end
    ord = ord(1:min(EXPORT_CAP, numel(ord)));
    m = numel(ord);
    M1 = strings(m,1); M2 = strings(m,1); Dn = strings(m,1);
    Ln = strings(m,1); Tn = strings(m,1);
    for i = 1:m
        j = ord(i);
        M1(i) = string(i_asChar(res.detail(j).M1));
        M2(i) = string(i_asChar(res.detail(j).M2));
        Dn(i) = string(i_asChar(res.detail(j).D));
        Ln(i) = string(i_asChar(res.detail(j).L));
        Tn(i) = string(i_asChar(res.detail(j).T));
    end
    T = table(res.eff(ord), res.powerDens(ord), res.loss(ord), res.lossDens(ord), ...
        M1, M2, Dn, Ln, Tn, ...
        'VariableNames', {'EffPct','PowerDensWL','LossW','LossDensWL', ...
                          'MosfetI','MosfetII','Diode','Inductor','Transformer'});
end


function tbl = i_toTable(src, powerField, volField, kind)
    n = numel(src);
    if n == 0
        tbl = table('Size',[0 3], ...
            'VariableTypes', {'string','double','double'}, ...
            'VariableNames', {'Identifier','PowerW','Volume_cm3'});
        return
    end
    ids = strings(n,1); pw = zeros(n,1); vol = zeros(n,1);
    for i = 1:n
        ids(i) = i_identifier(src(i), kind);
        pw(i)  = src(i).(powerField);
        vol(i) = src(i).(volField);
    end
    tbl = table(ids, pw, vol, 'VariableNames', {'Identifier','PowerW','Volume_cm3'});
end


function str = i_identifier(r, kind)
% Build a FULL constructive label per component family - all the build details
% that appear in each component's own tab, so the combo TABLE alone is enough to
% build the prototype. (The chart datatip stays clean; it only shows the row
% number.) Each cell is a long string; the table scrolls horizontally.
    switch kind
        case 'semi'
            coolShort = 'N';
            if strcmpi(i_asChar(r.Method), 'Forced'), coolShort = 'F'; end
            q = 1;
            if isfield(r,'DevicesPerHS') && r.DevicesPerHS > 0, q = r.DevicesPerHS; end
            air = '';
            if coolShort == 'F' && isfield(r,'AirSpeed')
                a = strtrim(char(string(r.AirSpeed)));
                if ~isempty(a), air = ['(' a ')']; end
            end
            vmax = NaN;
            if isfield(r,'BlockVolt_V'),   vmax = r.BlockVolt_V;
            elseif isfield(r,'MaxVolt_V'), vmax = r.MaxVolt_V; end
            grp = r.PowerW; if isfield(r,'GroupLossW'), grp = r.GroupLossW; end
            str = string(sprintf(['%dx %s [%s, %s] | HS %s (%s) %.0fmm %s%s | ' ...
                'Rth=%.2fC/W Tr=%.0fC Vmax=%.0fV | group loss=%.1fW'], ...
                q, i_asChar(r.PartNumber), i_asChar(r.Producer), i_asChar(r.Package), ...
                i_asChar(r.Heatsink), i_asChar(r.HeatsinkProducer), r.Length_mm, ...
                coolShort, air, r.Rth_C_W, r.Temp_Elev_C, vmax, grp));
        case 'inductor'
            str = string(sprintf(['%s core#%s | mu=%g N=%d Nparal=%d stacks=%d | ' ...
                'Ku=%.2f dT=%.0fC fs=%.0fkHz | Vol=%.1fcm3 loss=%.2fW'], ...
                i_asChar(r.MaterialTag), i_asChar(r.ID), r.mi, r.N, r.Nparal, r.Stacks, ...
                r.Ku, r.DeltaT, r.fs/1000, r.Vol, r.Ptotal));
        case 'transformer'
            str = string(sprintf(['%s core#%s [%s, par=%d] | Np=%d Ns=%d Bm=%.2fT | ' ...
                'Ku=%.2f dT=%.0fC | Vol=%.1fcm3 Pcore=%.2f Pcu=%.2f loss=%.2fW'], ...
                i_asChar(r.Material), i_asChar(r.Size), i_asChar(r.Geometry), r.ParallelCores, ...
                r.Np, r.Ns, r.Bm, r.Ku, r.DeltaT, r.VolTotal, r.PnucleoSE, r.Pcond, r.Ptrafo));
        otherwise
            str = string(i_asChar(r.(kind)));
    end
end


function tbl = i_capByLoss(tbl, capN, mode)
% Reduce a family to at most capN rows.
%   'spread' (default) - capN rows evenly sampled across the loss range, so the
%                        combination keeps the full trade-off cloud (best, worst
%                        and middle), like the original tool.
%   'top'              - the capN lowest-loss rows (the very best designs).
%   'all'              - no reduction (every record).
    if nargin < 3, mode = 'spread'; end
    if strcmp(mode, 'all') || height(tbl) <= capN, return; end
    [~, order] = sort(tbl.PowerW);
    if strcmp(mode, 'top')
        tbl = tbl(order(1:capN), :);
    else
        pick = unique(round(linspace(1, numel(order), capN)));
        tbl = tbl(order(pick), :);
    end
end


function s = i_asChar(v)
    if istable(v),      v = v{1,1};      end
    if iscell(v),       v = v{1};        end
    if isstring(v),     s = char(v);     return; end
    if isnumeric(v) || islogical(v), s = num2str(v); return; end   % numeric id -> "9928", not char(9928)
    s = char(v);
end


function r = i_root()
    r = pdpwr.util.data_root();   % source tree OR ctfroot (compiled .exe)
end
