function P = pcore_magmattec(material, fs_kHz, Bpk_G)
%PCORE_MAGMATTEC Empirical core-loss interpolation for Magmattec materials.
%
%   P = pdpwr.loss.pcore_magmattec(material, fs_kHz, Bpk_G)
%
%   material - '002', '026', '034' or '052'
%   fs_kHz   - switching frequency [kHz]
%   Bpk_G    - peak flux density [Gauss]
%
%   Returns core-loss density [mW/cm^3]. Returns NaN if the result would fall
%   below 10 mW/cm^3 (out-of-validity region) - mirrors legacy behaviour.
%
%   Datapoints come from the Magmattec material datasheets and reproduce the
%   curves embedded in app2's pcore002/026/034/052 functions, BUT now each
%   material correctly maps to its own dataset (legacy app always called
%   pcore002 due to a bug).

    persistent curves
    if isempty(curves)
        % MATLAB struct field names cannot start with a digit, so prefix 'm'.
        curves = struct( ...
            'm002', i_dataset_002(), ...
            'm026', i_dataset_026(), ...
            'm034', i_dataset_034(), ...
            'm052', i_dataset_052());
    end

    fieldName = ['m' material];
    if ~isfield(curves, fieldName)
        error('pdpwr:pcoreMatUnknown', 'Unknown Magmattec material %s', material);
    end

    data = curves.(fieldName);
    P = i_interpolate(data, fs_kHz, Bpk_G);
    if P < 10, P = NaN; end
end


function P = i_interpolate(data, fs_kHz, Bpk_G)
% Fast bilinear interpolation: first interpolate each frequency curve at the
% requested Bpk (4 interp1 calls), then interpolate across frequency (1 call).
% This replaces the old 1000-point curve reconstruction that ran on EVERY
% design evaluation and made the Magmattec sweep extremely slow.
    nf = numel(data.freqs);
    if any(data.freqs == fs_kHz)
        idx = find(data.freqs == fs_kHz, 1);
        P = interp1(data.curves{idx}.x, data.curves{idx}.y, Bpk_G, 'linear', 'extrap');
        return
    end
    samples = zeros(nf, 1);
    for k = 1:nf
        samples(k) = interp1(data.curves{k}.x, data.curves{k}.y, Bpk_G, 'linear', 'extrap');
    end
    % Clamp the frequency to the tabulated range to avoid wild extrapolation.
    fclamped = min(max(fs_kHz, data.freqs(1)), data.freqs(end));
    P = interp1(data.freqs, samples, fclamped, 'linear');
end


function d = i_dataset_002()
    d.freqs = [50, 100, 250, 500];
    d.curves = {
        struct('x', [200,300,400,500,600,1000,2000,4000],          'y', [20,50,100,180,250,700,3000,10000]);
        struct('x', [150,200,300,400,600,700,800,1000,1500,2000,2500], 'y', [20,45,120,200,500,700,900,1500,3000,6000,9000]);
        struct('x', [68,90,140,200,300,400,500,700,900,1000,2000], 'y', [10,20,50,130,300,590,900,2000,3000,4000,9000]);
        struct('x', [50,60,70,100,130,200,300,500,600,700,1000],   'y', [12,18,28,60,100,300,700,2000,3000,4000,9000]);
    };
end


function d = i_dataset_026()
    d.freqs = [50, 100, 250, 500];
    d.curves = {
        struct('x', [82,200,400,600,700,1000,2000],                'y', [10,70,300,700,900,1800,7000]);
        struct('x', [55,90,100,200,300,400,650,1000,1500],         'y', [10,30,40,180,400,750,2000,4500,10000]);
        struct('x', [27,50,70,80,135,200,300,500,700],             'y', [10,40,80,110,300,700,3000,7000,9500]);
        struct('x', [15,20,30,40,60,100,300,400],                  'y', [10,20,50,90,200,600,5500,10000]);
    };
end


function d = i_dataset_034()
    d.freqs = [50, 100, 250, 500];
    d.curves = {
        struct('x', [68,80,102,150,200,300,400,500,700,900,1000],  'y', [10,20,30,80,180,500,1000,1700,4000,7500,10000]);
        struct('x', [50,70,100,150,250,300,400,600,700,750],       'y', [10,25,60,150,600,1000,2000,6000,8000,10000]);
        struct('x', [31,40,50,60,70,80,100,150,200,300,400,500],   'y', [10,19,30,50,70,100,190,500,1000,2900,6000,10000]);
        struct('x', [20,30,40,50,70,100,150,200,300,350],          'y', [10,28,50,90,200,450,1000,2500,6500,10000]);
    };
end


function d = i_dataset_052()
    d.freqs = [50, 100, 250, 500];
    d.curves = {
        struct('x', [85,100,150,200,300,400,500,600,700,1000,1500],            'y', [10,15,40,80,200,400,700,1100,2000,3500,8000]);
        struct('x', [60,80,100,150,200,250,300,350,400,500,600,800,1000],      'y', [10,20,35,80,180,300,450,700,900,1500,2400,4500,7500]);
        struct('x', [35,50,70,87,100,150,200,250,300,400,500,600,700],         'y', [10,22,58,80,110,250,550,900,1400,2600,4500,6800,9000]);
        struct('x', [21,30,35,40,50,60,70,100,150,200,300,350,450,490],        'y', [10,22,30,40,65,100,150,300,700,1500,3500,5000,8000,10000]);
    };
end
