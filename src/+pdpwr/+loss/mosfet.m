function loss = mosfet(plecsModel, op)
%MOSFET Switching + conduction losses for a SiC MOSFET (single device).
%
%   loss = pdpwr.loss.mosfet(plecsModel, op)
%
%   plecsModel - struct returned by pdpwr.util.plecs_load
%   op         - operating point struct with fields:
%       .Vd        Drain-source blocking voltage during commutation [V]
%       .Tj        Junction temperature [degC]
%       .Rg        External gate resistor [ohm]
%       .Vgson     Gate-source ON voltage [V] (for GeneSiC only; ignored for Wolfspeed)
%       .I_RMS     RMS device current [A]
%       .I_on      Instantaneous current at turn-on [A]
%       .I_off     Instantaneous current at turn-off [A]
%       .fs        Switching frequency [Hz]
%       .softSwitching  (optional, default false) if true, P_on is zeroed
%
%   Returns:
%     loss.Eon    [J]
%     loss.Eoff   [J]
%     loss.Rds_on equivalent on-resistance averaged across I_on/I_off [ohm]
%     loss.P_on   = fs * Eon          (or 0 if softSwitching) [W]
%     loss.P_off  = fs * Eoff         [W]
%     loss.P_cond = Rds_on * I_RMS^2  [W]
%     loss.P_total = P_on + P_off + P_cond [W]

    if ~isfield(op, 'softSwitching'), op.softSwitching = false; end
    if ~isfield(op, 'Vgson'),         op.Vgson = 15;            end

    Eon_J  = plecsModel.Eon (op.I_on,  op.Vd, op.Tj, op.Rg);
    Eoff_J = plecsModel.Eoff(op.I_off, op.Vd, op.Tj, op.Rg);

    % Equivalent Rds_on: average of Vdrop/I at on and off instants.
    % Approximation kept identical to the legacy code so regression matches.
    rds = 0.5 * ( plecsModel.Vdrop(op.I_on,  op.Vgson, op.Tj) / op.I_on ...
                + plecsModel.Vdrop(op.I_off, op.Vgson, op.Tj) / op.I_off );

    P_on  = op.fs * Eon_J;
    if op.softSwitching, P_on = 0; end
    P_off = op.fs * Eoff_J;
    P_cond = rds * op.I_RMS^2;

    loss = struct( ...
        'Eon',     Eon_J, ...
        'Eoff',    Eoff_J, ...
        'Rds_on',  rds, ...
        'P_on',    P_on, ...
        'P_off',   P_off, ...
        'P_cond',  P_cond, ...
        'P_total', P_on + P_off + P_cond);
end
