function P = core(stein, fs, Bpk, Tcore, Vol_mm3)
%CORE Original (Steinmetz) core loss in watts.
%
%   P = pdpwr.loss.core(stein, fs, Bpk, Tcore, Vol_mm3)
%
%   stein - one row of catalog.steinmetz (struct with fields alpha, beta,
%           k, c1_T, c2_T, c3_T)
%   fs    - switching frequency [Hz]
%   Bpk   - peak flux density [T]
%   Tcore - core temperature [degC]
%   Vol_mm3 - core volume [mm^3]
%
%   P_v = k * fs^alpha * Bpk^beta * (c1 - c2*T + c3*T^2)   [W/m^3]
%   P   = P_v * (Vol_mm3 * 1e-9)                            [W]
%
%   Coefficients come from the Magnetics Curve-Fit Tool: fs in [kHz] in the
%   original tool, but Steinmetz sheet stores alpha/beta tuned for SI units
%   so we keep fs in Hz consistently with the trafo loop in app2.

    Pv_kW_per_m3 = stein.k .* fs.^stein.alpha .* Bpk.^stein.beta ...
                 .* (stein.c1_T - stein.c2_T .* Tcore + stein.c3_T .* Tcore.^2);
    % coefficients sheet historically returns P in kW/m^3; convert to W:
    P = Pv_kW_per_m3 .* (Vol_mm3 .* 1e-9) .* 1000;
end
