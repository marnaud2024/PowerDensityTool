function loss = diode(diodeRow, op)
%DIODE Conduction losses for a SiC Schottky diode.
%
%   loss = pdpwr.loss.diode(diodeRow, op)
%
%   diodeRow - one row of catalog.diodes (struct or table row).
%              Required columns:
%                 Rd_a, Rd_b, Rd_c          (R_d(Tj)   = a*Tj^2 + b*Tj + c)
%                 Vto_a, Vto_b, Vto_c       (V_TO(Tj)  = a*Tj^2 + b*Tj + c)
%                 PerLeg ('NÃO' or 'SIM' - if SIM, current is split between 2 dies)
%   op       - operating point:
%                 .Tj       Junction temperature [degC]
%                 .I_RMS    RMS current [A]
%                 .I_avg    Average current [A]
%
%   Returns:
%     loss.R_d        Effective on-resistance at Tj [ohm]
%     loss.V_TO       Effective threshold voltage at Tj [V]
%     loss.P_cond     Conduction loss [W]
%     loss.PerLeg     true if device is internally a half-leg (2 dies)

    % Resistance and threshold voltage as quadratic functions of Tj
    Tj = op.Tj;
    Rd  = diodeRow.Rd_a  * Tj^2 + diodeRow.Rd_b  * Tj + diodeRow.Rd_c;
    Vto = diodeRow.Vto_a * Tj^2 + diodeRow.Vto_b * Tj + diodeRow.Vto_c;

    perLegStr = i_asScalarChar(diodeRow.PerLeg);
    isPerLeg  = strcmpi(strtrim(perLegStr), 'SIM');

    if isPerLeg
        % Device has 2 dies in a half-bridge package; current splits in 2
        Pcond = 2 * ( Rd * (op.I_RMS/2)^2 + Vto * (op.I_avg/2) );
    else
        Pcond = Rd * op.I_RMS^2 + Vto * op.I_avg;
    end

    loss = struct( ...
        'R_d',     Rd, ...
        'V_TO',    Vto, ...
        'P_cond',  Pcond, ...
        'P_total', Pcond, ...      % SiC Schottky: no recovery losses
        'PerLeg',  isPerLeg);
end


function s = i_asScalarChar(v)
% Coerce table cell / string / char to a plain char vector
    if iscell(v),       s = v{1};
    elseif isstring(v), s = char(v);
    else,               s = char(v);
    end
end
