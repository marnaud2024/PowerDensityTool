function props = awg_props(awg, awgTable)
%AWG_PROPS Look up AWG wire properties (resistance, area, diameter).
%
%   props = pdpwr.util.awg_props(awg)
%   props = pdpwr.util.awg_props(awg, awgTable)
%
%   awg       - AWG number (10..44)
%   awgTable  - optional, table loaded from Catalog AWG_Table sheet
%               (if omitted, the catalog is read on the fly)
%
%   Returns a struct with fields:
%     .awg        AWG number
%     .r_ohm_m    Resistance per metre at 20 degC [ohm/m]
%     .A_cm2      Wire cross section [cm^2]
%     .D_cm       Wire external diameter (incl. insulation) [cm]

    if nargin < 2 || isempty(awgTable)
        cat = pdpwr.util.load_catalog();
        awgTable = cat.awg;
    end

    idx = find(awgTable.AWG == awg, 1);
    if isempty(idx)
        error('pdpwr:awgUnknown', 'AWG %g not present in AWG_Table.', awg);
    end

    props = struct( ...
        'awg',     awg, ...
        'r_ohm_m', awgTable.r_awg_ohm_per_m(idx), ...
        'A_cm2',   awgTable.Aawg_cm2(idx), ...
        'D_cm',    awgTable.Dext_cm(idx));
end
