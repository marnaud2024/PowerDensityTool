function net = load_neural_net(dataDir, materialIdx)
%LOAD_NEURAL_NET Load the TDK ferrite core-loss neural network weights.
%
%   net = pdpwr.util.load_neural_net(dataDir, materialIdx)
%   net = pdpwr.util.load_neural_net()   % defaults to ../data/ and Idx=NaN
%
%   Loads w.mat, b.mat, min_b.mat, max_b.mat, min_freq.mat, max_freq.mat,
%   min_t.mat, max_t.mat, min_out.mat, max_out.mat from `dataDir`.
%
%   The struct returned packages everything in a single object that can
%   be passed to pdpwr.design.transformer through opts.neuralNet.

    if nargin < 1 || isempty(dataDir)
        % data_root() works from source AND from the compiled .exe (ctfroot).
        dataDir = fullfile(pdpwr.util.data_root(), 'data', 'neural_net');
    end
    if nargin < 2, materialIdx = NaN; end

    requiredFiles = {'w.mat', 'b.mat', 'min_b.mat', 'max_b.mat', ...
                     'min_freq.mat', 'max_freq.mat', 'min_t.mat', 'max_t.mat', ...
                     'min_out.mat', 'max_out.mat'};
    for k = 1:numel(requiredFiles)
        p = fullfile(dataDir, requiredFiles{k});
        if exist(p, 'file') ~= 2
            error('pdpwr:netMissing', 'Required neural-net file %s missing in %s', requiredFiles{k}, dataDir);
        end
    end

    s1 = load(fullfile(dataDir, 'w.mat'));        net.w        = s1.w;
    s2 = load(fullfile(dataDir, 'b.mat'));        net.b        = s2.b;
    s3 = load(fullfile(dataDir, 'min_b.mat'));    net.min_b    = s3.min_b;
    s4 = load(fullfile(dataDir, 'max_b.mat'));    net.max_b    = s4.max_b;
    s5 = load(fullfile(dataDir, 'min_freq.mat')); net.min_freq = s5.min_freq;
    s6 = load(fullfile(dataDir, 'max_freq.mat')); net.max_freq = s6.max_freq;
    s7 = load(fullfile(dataDir, 'min_t.mat'));    net.min_t    = s7.min_t;
    s8 = load(fullfile(dataDir, 'max_t.mat'));    net.max_t    = s8.max_t;
    s9 = load(fullfile(dataDir, 'min_out.mat'));  net.min_out  = s9.min_out;
    sA = load(fullfile(dataDir, 'max_out.mat'));  net.max_out  = sA.max_out;

    net.materialIdx = materialIdx;
    % Material -> i1 index used by app2 ButtonPushed:
    %  R=1, P=2, F=3, T=4, N27=5, N41=6, N49=7, N72=8, N87=9, N92=10, N95=11, N97=12, 139=13
    net.materialIndex = struct( ...
        'R',1,'P',2,'F',3,'T',4, ...
        'N27',5,'N41',6,'N49',7,'N72',8,'N87',9,'N92',10,'N95',11,'N97',12, ...
        'M139',13);
end
