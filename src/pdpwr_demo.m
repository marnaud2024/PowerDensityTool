function pdpwr_demo()
%PDPWR_DEMO Sanity-check the +pdpwr package on a single design point.
%
%   Run from the PowerDensityTool/src folder:
%       cd 'C:\Users\Arnaud\Downloads\SOBRAEP\PowerDensityTool\src'
%       pdpwr_demo
%
%   This is NOT the final UI - it just exercises every core function on one
%   representative case so you can spot-check the new pdpwr.* package works
%   end-to-end before we wire up the new app.

    fprintf('Loading catalog...\n');
    cat = pdpwr.util.load_catalog();
    fprintf('  %d mosfet models, %d diodes, %d heatsinks, %d magnetics, %d trafos\n', ...
        height(cat.mosfets), height(cat.diodes), height(cat.heatsinks), ...
        height(cat.magnetics), height(cat.trafos));

    % --- MOSFET single device loss ---
    mosfetRow = cat.mosfets(strcmp(cat.mosfets.PartNumber, 'G3R40MT12K'), :);
    if height(mosfetRow) == 0
        warning('G3R40MT12K not in catalog'); return;
    end
    rootDir = fileparts(fileparts(mfilename('fullpath')));
    xmlRel = i_asChar(mosfetRow.XML_File);
    vendor = i_asChar(mosfetRow.Manufacturer);
    xmlPath = fullfile(rootDir, 'data', xmlRel);
    plecsModel = pdpwr.util.plecs_load(xmlPath, vendor);

    op = struct('Vd',800,'Tj',125,'Rg',7,'Vgson',15, ...
                'I_RMS',22,'I_on',30,'I_off',30,'fs',50e3,'softSwitching',false);
    Lm = pdpwr.loss.mosfet(plecsModel, op);
    fprintf('\nMOSFET %s @ Vd=%g Tj=%g fs=%g kHz:\n', mosfetRow.PartNumber, op.Vd, op.Tj, op.fs/1000);
    fprintf('  Eon=%.4f mJ  Eoff=%.4f mJ  Rds=%.4f mOhm\n', Lm.Eon*1000, Lm.Eoff*1000, Lm.Rds_on*1000);
    fprintf('  Pon=%.2f W  Poff=%.2f W  Pcond=%.2f W  P_total=%.2f W\n', ...
        Lm.P_on, Lm.P_off, Lm.P_cond, Lm.P_total);

    % --- Diode single device loss ---
    diodeRow = cat.diodes(strcmp(cat.diodes.PartNumber, 'GD60MPS06H'), :);
    if height(diodeRow) > 0
        Ld = pdpwr.loss.diode(table2struct(diodeRow), struct('Tj',125,'I_RMS',57,'I_avg',34));
        partName = i_asChar(diodeRow.PartNumber);
        fprintf('\nDiode %s @ Tj=125 I=57Arms 34Amed:\n', partName);
        fprintf('  Rd=%.4g Ohm  Vto=%.4g V  P_cond=%.2f W (PerLeg=%d)\n', Ld.R_d, Ld.V_TO, Ld.P_cond, Ld.PerLeg);
    end

    % --- Heatsink design ---
    hsOp = struct('Tj',125,'T_amb',55,'T_HS_max',100,'Qtdd',12, ...
                  'L_min',0.001,'L_max',300,'Rth_jc',1,'Rth_chs',0.5, ...
                  'convection','Natural');
    fits = pdpwr.design.heatsink(Lm.P_total, hsOp, cat.heatsinks);
    fprintf('\nHeatsink: %d profile fits for P=%.1f W (%d devices)\n', numel(fits), Lm.P_total, hsOp.Qtdd);
    for k = 1:min(3, numel(fits))
        fprintf('  %s (%s) L=%.1f mm  Rth=%.3f C/W  V=%.1f cm^3\n', ...
            fits(k).profile, fits(k).manufacturer, fits(k).length_mm, fits(k).Rth_HA, fits(k).volume_cm3);
    end

    fprintf('\nDemo OK.\n');
end


function s = i_asChar(v)
% Coerce a 1-row table cell / string / char into a plain char vector
    if istable(v),       v = v{1, 1};      end
    if iscell(v),        v = v{1};         end
    if isstring(v),      s = char(v);      return; end
    if isnumeric(v) || islogical(v), s = num2str(v); return; end
    s = char(v);
end

