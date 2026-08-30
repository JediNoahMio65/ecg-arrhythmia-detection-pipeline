%RUNSECTION3  Reference ECG preprocessing pipeline on a MIT-BIH record.
%
%   Reads a MIT-BIH record with the MATLAB WFDB readers in matlab/io,
%   verifies the decode against the values the header declares and against
%   the C++ test fixture, runs the reference denoising chain, reports what
%   the chain did to the signal, and saves a four-panel figure.
%
%   Run it from anywhere:
%       run('matlab/scripts/runSection3.m')
%
%   The record files are expected in <root>/data/mitdb, which is gitignored.
%   Download them with:
%       curl -O https://physionet.org/files/mitdb/1.0.0/100.hea
%       curl -O https://physionet.org/files/mitdb/1.0.0/100.dat
%       curl -O https://physionet.org/files/mitdb/1.0.0/100.atr

%% Setup
clearvars
close all

thisDir = fileparts(mfilename('fullpath'));
matlabDir = fileparts(thisDir);
addpath(matlabDir);
addEcgPaths();

projectRoot = ecgProjectRoot();
recordName = '100';
channel = 1;                 % MLII
dataDir = fullfile(projectRoot, 'data', 'mitdb');
figureDir = fullfile(matlabDir, 'figures');
fixturePath = fullfile(projectRoot, 'cpp', 'tests', 'data', ...
    '100.atr.reference.csv');

headerPath = fullfile(dataDir, [recordName '.hea']);
if exist(headerPath, 'file') ~= 2
    error('runSection3:missingData', ...
        ['Record files not found in %s\n' ...
         'Download 100.hea, 100.dat and 100.atr from ' ...
         'https://physionet.org/content/mitdb/1.0.0/'], dataDir);
end

fprintf('\n===== Section 3: MATLAB reference pipeline =====\n\n');

%% Read the record
hdr = readWfdbHeader(headerPath);
[physical, raw] = readWfdbSignal(fullfile(dataDir, [recordName '.dat']), hdr);
ann = readWfdbAnnotations(fullfile(dataDir, [recordName '.atr']));

fs = hdr.samplingFrequency;
x = physical(:, channel);
leadName = hdr.signals(channel).description;
t = (0:numel(x) - 1).' / fs;

fprintf('record              %s\n', hdr.recordName);
fprintf('sampling frequency  %g Hz\n', fs);
fprintf('record length       %d samples (%.2f s)\n', ...
    hdr.numSamples, hdr.durationSeconds);
fprintf('signals             %d\n', hdr.numSignals);
fprintf('analysed channel    %d (%s)\n\n', channel, leadName);

%% Verify the signal decode against the header
fprintf('signal decode verification\n');
allSignalsOk = true;
for k = 1:hdr.numSignals
    s = hdr.signals(k);
    computed = wfdbChecksum16(raw(:, k));
    initialOk = raw(1, k) == s.initialValue;
    checksumOk = computed == s.checksum;
    allSignalsOk = allSignalsOk && initialOk && checksumOk;
    fprintf('  %-5s initial %6d/%6d  checksum %7d/%7d  %s\n', ...
        s.description, raw(1, k), s.initialValue, computed, s.checksum, ...
        localVerdict(initialOk && checksumOk));
end
fprintf('  overall %s\n\n', localVerdict(allSignalsOk));

%% Verify the annotation decode against the C++ fixture
beats = ann(ann.isBeat, :);
fprintf('annotations         %d (%d beats)\n', height(ann), height(beats));

if exist(fixturePath, 'file') == 2
    cmp = compareWfdbAnnotationFixture(ann, fixturePath);
    fprintf('cross-language check against cpp/tests/data/%s\n', ...
        '100.atr.reference.csv');
    fprintf('  %d fixture rows, %d decoded rows, %d mismatches  %s\n', ...
        cmp.fixtureRows, cmp.decodedRows, cmp.mismatches, ...
        localVerdict(cmp.identical));
    if ~cmp.identical && ~isempty(cmp.firstMismatch)
        fprintf('  first difference: %s\n', cmp.firstMismatch);
    end
else
    fprintf('cross-language check skipped, fixture not found\n');
end
fprintf('\n');

%% Beat composition
[classes, ~, classIdx] = unique(beats.aami);
classCounts = accumarray(classIdx, 1);
fprintf('AAMI beat classes\n');
for k = 1:numel(classes)
    fprintf('  %-2s %5d  %5.1f%%\n', classes{k}, classCounts(k), ...
        100 * classCounts(k) / height(beats));
end
fprintf('\n');

%% Preprocess
[clean, info] = preprocessEcg(x, fs);
st = info.settings;

fprintf('preprocessing settings\n');
fprintf('  baseline medians    %d and %d samples (%.0f and %.0f ms)\n', ...
    st.baselineShortWindow, st.baselineLongWindow, ...
    1000 * st.baselineShortWindow / fs, 1000 * st.baselineLongWindow / fs);
fprintf('  bandpass            %.1f to %.1f Hz, Butterworth order %d, zero phase\n', ...
    st.bandLow, st.bandHigh, st.filterOrder);
fprintf('  notch               %.0f Hz, Q = %.0f, applied: %s\n\n', ...
    st.notchFrequency, st.notchQ, localYesNo(st.notchApplied));

%% Quantify the effect, excluding filter edge transients
guard = round(2 * fs);
keep = (guard + 1):(numel(x) - guard);
xg = x(keep);
cg = clean(keep);

bands = { ...
    'below 0.5 Hz',   0,    0.5; ...
    '0.5 to 40 Hz',   0.5,  40; ...
    '59 to 61 Hz',    59,   61; ...
    'above 40 Hz',    40,   fs / 2};

fprintf('share of total power by band (interior of the record)\n');
fprintf('  %-14s %10s %10s %10s\n', 'band', 'raw', 'cleaned', 'change');
for k = 1:size(bands, 1)
    before = bandPowerFraction(xg, fs, bands{k, 2}, bands{k, 3});
    after  = bandPowerFraction(cg, fs, bands{k, 2}, bands{k, 3});
    if after > 0 && before > 0
        changeText = sprintf('%8.1fx', after / before);
    else
        changeText = '        -';
    end
    fprintf('  %-14s %10.6f %10.6f %10s\n', ...
        bands{k, 1}, before, after, changeText);
end
fprintf('\n');

fprintf('amplitude\n');
fprintf('  rms raw             %.4f mV\n', sqrt(mean(xg .^ 2)));
fprintf('  rms cleaned         %.4f mV\n', sqrt(mean(cg .^ 2)));
fprintf('  baseline estimate   %.3f to %.3f mV\n', ...
    min(info.baseline), max(info.baseline));
fprintf('  correlation         %.4f\n\n', localCorr(xg, cg));

%% Confirm the R peaks did not move
searchWindow = round(0.050 * fs);
interior = beats.sample(beats.sample > guard & ...
    beats.sample < numel(x) - guard);
offsets = zeros(numel(interior), 1);
peakAmplitude = zeros(numel(interior), 1);
for k = 1:numel(interior)
    % Annotation sample numbers are 0-based, so add 1 to index MATLAB.
    centre = interior(k) + 1;
    lo = centre - searchWindow;
    hi = centre + searchWindow;
    [peakAmplitude(k), pos] = max(clean(lo:hi));
    offsets(k) = pos - searchWindow - 1;
end

withinFive = 100 * mean(abs(offsets) <= 5);
fprintf('R peak alignment after filtering (%d interior beats)\n', ...
    numel(interior));
fprintf('  median offset       %d samples\n', median(offsets));
fprintf('  within +/-5 samples %.2f%%\n', withinFive);
fprintf('  mean peak amplitude %.3f mV\n\n', mean(peakAmplitude));

%% Figure
if exist(figureDir, 'dir') ~= 7
    mkdir(figureDir);
end

% Centre the time-domain panels on the most interesting beat available:
% a ventricular ectopic if the record has one, otherwise a supraventricular
% ectopic, otherwise the first beat.
focus = localPickFocusBeat(beats);
windowSeconds = 10;
startSample = max(1, focus + 1 - round(windowSeconds / 2 * fs));
stopSample = min(numel(x), startSample + round(windowSeconds * fs) - 1);
view = startSample:stopSample;

fig = figure('Position', [100, 100, 1500, 950], 'Color', 'w');
layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(layout, sprintf(['MIT-BIH record %s, lead %s: reference ' ...
    'preprocessing pipeline'], hdr.recordName, leadName), ...
    'FontWeight', 'bold', 'FontSize', 14);

% Panel 1: raw signal with the estimated baseline
ax1 = nexttile(layout);
plot(ax1, t(view), x(view), 'Color', [0.45, 0.45, 0.45], 'LineWidth', 0.8);
hold(ax1, 'on');
plot(ax1, t(view), info.baseline(view), 'Color', [0.85, 0.20, 0.15], ...
    'LineWidth', 2);
hold(ax1, 'off');
grid(ax1, 'on');
xlabel(ax1, 'time (s)');
ylabel(ax1, 'amplitude (mV)');
title(ax1, 'Raw signal with estimated baseline wander');
legend(ax1, {'raw', 'baseline estimate'}, 'Location', 'best');
xlim(ax1, [t(view(1)), t(view(end))]);

% Panel 2: cleaned signal with annotated beats
ax2 = nexttile(layout);
plot(ax2, t(view), clean(view), 'Color', [0.10, 0.35, 0.65], 'LineWidth', 1.0);
hold(ax2, 'on');
inView = beats.sample >= view(1) - 1 & beats.sample <= view(end) - 1;
shown = beats(inView, :);
for k = 1:height(shown)
    idx = shown.sample(k) + 1;
    isNormal = strcmp(shown.aami{k}, 'N');
    if isNormal
        markerColour = [0.15, 0.55, 0.25];
    else
        markerColour = [0.85, 0.20, 0.15];
    end
    plot(ax2, t(idx), clean(idx), 'v', 'MarkerSize', 7, ...
        'MarkerFaceColor', markerColour, 'MarkerEdgeColor', 'none');
    text(ax2, t(idx), clean(idx), ['  ' shown.symbol{k}], ...
        'Color', markerColour, 'FontWeight', 'bold', ...
        'VerticalAlignment', 'bottom');
end
hold(ax2, 'off');
grid(ax2, 'on');
xlabel(ax2, 'time (s)');
ylabel(ax2, 'amplitude (mV)');
title(ax2, 'Cleaned signal with reference beat labels');
xlim(ax2, [t(view(1)), t(view(end))]);

% Panel 3: spectra before and after
ax3 = nexttile(layout);
spectrumSeconds = 60;
nSpec = min(numel(xg), round(spectrumSeconds * fs));
[fAxis, rawSpec] = localSpectrum(xg(1:nSpec), fs);
[~, cleanSpec] = localSpectrum(cg(1:nSpec), fs);
semilogy(ax3, fAxis, rawSpec, 'Color', [0.45, 0.45, 0.45], 'LineWidth', 0.9);
hold(ax3, 'on');
semilogy(ax3, fAxis, cleanSpec, 'Color', [0.10, 0.35, 0.65], 'LineWidth', 0.9);
xline(ax3, st.notchFrequency, '--', sprintf('%.0f Hz', st.notchFrequency), ...
    'Color', [0.85, 0.20, 0.15], 'LabelVerticalAlignment', 'bottom');
xline(ax3, st.bandHigh, ':', sprintf('%.0f Hz', st.bandHigh), ...
    'Color', [0.30, 0.30, 0.30], 'LabelVerticalAlignment', 'bottom');
hold(ax3, 'off');
grid(ax3, 'on');
xlim(ax3, [0, 100]);
xlabel(ax3, 'frequency (Hz)');
ylabel(ax3, 'amplitude (mV, log scale)');
title(ax3, sprintf('Amplitude spectrum, first %d s of the interior', ...
    round(nSpec / fs)));
legend(ax3, {'raw', 'cleaned'}, 'Location', 'northeast');

% Panel 4: how far the R peaks moved
ax4 = nexttile(layout);
edges = -10.5:1:10.5;
histogram(ax4, offsets, edges, 'FaceColor', [0.10, 0.35, 0.65], ...
    'EdgeColor', 'none');
grid(ax4, 'on');
xlabel(ax4, 'peak offset from annotation (samples)');
ylabel(ax4, 'beats');
title(ax4, sprintf(['R peak offset after filtering: %.2f%% within ' ...
    '5 samples'], withinFive));
xlim(ax4, [-10.5, 10.5]);

figurePath = fullfile(figureDir, 'section3_preprocessing.png');
exportgraphics(fig, figurePath, 'Resolution', 200);
fprintf('figure saved to %s\n\n', figurePath);

fprintf('===== Section 3 complete =====\n\n');


%% Local functions
function s = localVerdict(ok)
if ok
    s = 'PASS';
else
    s = 'FAIL';
end
end


function s = localYesNo(tf)
if tf
    s = 'yes';
else
    s = 'no';
end
end


function r = localCorr(a, b)
%LOCALCORR  Pearson correlation without requiring Statistics Toolbox.
a = a(:) - mean(a);
b = b(:) - mean(b);
denominator = sqrt(sum(a .^ 2) * sum(b .^ 2));
if denominator == 0
    r = 0;
else
    r = sum(a .* b) / denominator;
end
end


function sample = localPickFocusBeat(beats)
%LOCALPICKFOCUSBEAT  Sample number of the most illustrative beat available.
idx = find(strcmp(beats.aami, 'V'), 1, 'first');
if isempty(idx)
    idx = find(strcmp(beats.aami, 'S'), 1, 'first');
end
if isempty(idx)
    idx = 1;
end
sample = beats.sample(idx);
end


function [freq, amplitude] = localSpectrum(x, fs)
%LOCALSPECTRUM  Single-sided amplitude spectrum with a Hann window.
%   Written out with FFT so that no toolbox is needed.
x = x(:) - mean(x);
n = numel(x);
window = 0.5 - 0.5 * cos(2 * pi * (0:n - 1).' / (n - 1));
windowed = x .* window;

spectrum = fft(windowed);
half = floor(n / 2) + 1;
% Scale by the window's coherent gain so the amplitudes stay meaningful.
amplitude = abs(spectrum(1:half)) / sum(window) * 2;
freq = (0:half - 1).' * (fs / n);
end
