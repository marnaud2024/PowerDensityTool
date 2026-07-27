function res = heatsink(Ploss, op, hsTable)
%HEATSINK Dimension a heatsink profile given device losses and a thermal budget.
%
%   res = pdpwr.design.heatsink(Ploss, op, hsTable)
%
%   Ploss   - device loss (single device, single side) [W]
%   op      - operating conditions:
%        .Tj           Maximum junction temperature [degC]
%        .T_amb        Ambient temperature [degC]
%        .T_HS_max     Max allowed heatsink temperature [degC]
%        .Qtdd         Number of devices on the SAME heatsink (>=1)
%        .L_min, .L_max  Heatsink length bounds [mm]
%        .Rth_jc       Junction-to-case thermal resistance [degC/W] (default 1)
%        .Rth_chs      Case-to-heatsink thermal resistance [degC/W] (default 0.5)
%        .convection   'Natural' or 'Forced'
%   hsTable - catalog.heatsinks table
%
%   Returns an array of structs (one per valid heatsink profile) with:
%     .profile .manufacturer .convection .length_mm .Rth_HA .ElevTemp .volume_cm3

    if ~isfield(op, 'Rth_jc'),     op.Rth_jc = 1;     end
    if ~isfield(op, 'Rth_chs'),    op.Rth_chs = 0.5;  end
    if ~isfield(op, 'convection'), op.convection = 'Natural'; end

    deltaTallowed = op.T_HS_max - op.T_amb;
    if deltaTallowed <= 0 || op.Qtdd <= 0
        res = struct([]); return
    end

    % Required HS thermal resistance from device side
    T_HS_max_device = op.Tj - Ploss * (op.Rth_chs + op.Rth_jc);
    if T_HS_max_device - op.T_amb > deltaTallowed
        % Limited by the allowed HS temperature rise
        Rth_required = deltaTallowed / (op.Qtdd * Ploss);
        elevTemp = deltaTallowed - 0.1;
    else
        Rth_required = (T_HS_max_device - op.T_amb) / (op.Qtdd * Ploss);
        elevTemp = Rth_required * (op.Qtdd * Ploss);
    end
    if elevTemp <= 0 || elevTemp > deltaTallowed
        res = struct([]); return
    end

    isForced = strcmpi(op.convection, 'Forced');
    hasNotes = ismember('Convection_Notes', hsTable.Properties.VariableNames);

    res = repmat(struct( ...
            'profile', '', 'manufacturer', '', 'convection', '', ...
            'length_mm', NaN, 'Rth_HA', NaN, 'Rth_required', NaN, ...
            'ElevTemp', NaN, 'volume_cm3', NaN, 'air_speed', ''), 0, 1);

    for i = 1:height(hsTable)
        if isForced
            Rth_HA = hsTable.Rth_forced_CW(i);
        else
            Rth_HA = hsTable.Rth_natural_CW(i);
        end
        if isnan(Rth_HA) || Rth_HA <= 0, continue; end

        % HSDissipadores empirical length fit: L = 64.1030/(coef - 0.4258) + 14.754
        coef = Rth_required / Rth_HA;
        Lmm  = 64.1030 / (coef - 0.4258) + 14.754;
        if ~isfinite(Lmm) || Lmm < op.L_min || Lmm > op.L_max, continue; end

        H = hsTable.Height_mm(i);
        W = hsTable.Width_mm(i);
        Vol_cm3 = (Lmm / 10) * (H / 10) * (W / 10);

        % Forced-convection profiles in the catalog record their reference
        % air speed (e.g. "5 m/s") in the Convection_Notes column; natural
        % convection has no air flow.
        if isForced && hasNotes
            airSpeed = strtrim(char(string(hsTable.Convection_Notes(i))));
            if isempty(airSpeed), airSpeed = '5 m/s'; end
        else
            airSpeed = 'natural';
        end

        res(end+1, 1) = struct( ...
            'profile',      char(hsTable.Profile(i)), ...
            'manufacturer', char(hsTable.Manufacturer(i)), ...
            'convection',   op.convection, ...
            'length_mm',    Lmm, ...
            'Rth_HA',       Rth_HA, ...
            'Rth_required', Rth_required, ...
            'ElevTemp',     elevTemp, ...
            'volume_cm3',   Vol_cm3, ...
            'air_speed',    airSpeed);  %#ok<AGROW>
    end
end
