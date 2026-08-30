function [clean, info] = preprocessEcg(x, fs, varargin)
%PREPROCESSECG  Reference denoising chain for a single ECG channel.
%
%   CLEAN = PREPROCESSECG(X, FS) removes baseline wander, restricts the
%   signal to the diagnostic band, and suppresses powerline interference.
%   CLEAN is the same length and orientation as X.
%
%   [CLEAN, INFO] = PREPROCESSECG(...) also returns a struct holding every
%   intermediate stage and the exact filter coefficients used, so that the
%   pipeline can be inspected, plotted, or reproduced:
%
%       info.baseline    estimated baseline wander
%       info.detrended   x - baseline
%       info.banded      detrended signal after the bandpass
%       info.clean       final output, same as CLEAN
%       info.settings    struct of the options actually applied
%       info.bandpass    struct with fields b and a
%       info.notch       struct with fields b and a
%
%   Name-value options
%   ------------------
%       'BandLow'          0.5   lower passband edge in Hz
%       'BandHigh'         40    upper passband edge in Hz
%       'FilterOrder'      2     Butterworth order per edge
%       'NotchFrequency'   60    powerline frequency in Hz; use 50 in Europe
%       'NotchQ'           35    notch quality factor
%       'BaselineShort'    0.200 first median window in seconds
%       'BaselineLong'     0.600 second median window in seconds
%       'ApplyNotch'       true  set false to skip the notch stage
%
%   Why these three stages
%   ----------------------
%   1. Baseline wander is low-frequency drift from respiration and electrode
%      movement. It is estimated with two cascaded moving medians rather than
%      a high-pass filter. A median is insensitive to the QRS complex, which
%      is short and tall, so it tracks the drift without eroding the R peak
%      amplitude that a steep high-pass filter would distort. The short
%      window spans a QRS complex and the long window spans a full beat.
%
%   2. A zero-phase Butterworth bandpass keeps roughly 0.5 to 40 Hz, the
%      conventional diagnostic band for this kind of analysis. FILTFILT runs
%      the filter forwards and backwards, which squares the magnitude
%      response but cancels the phase entirely. That matters here: a filter
%      that shifted the signal in time would move every R peak away from the
%      sample number its annotation refers to, and every later detector
%      evaluation would inherit that offset.
%
%   3. A narrow notch removes mains interference. MIT-BIH was recorded in the
%      United States, so the default is 60 Hz.
%
%   Requires Signal Processing Toolbox for BUTTER and FILTFILT. The baseline
%   stage uses MOVMEDIAN and the notch is designed by NOTCHBIQUAD, both of
%   which avoid any further toolbox dependency.

p = inputParser;
p.addRequired('x', @(v) isnumeric(v) && isvector(v) && ~isempty(v));
p.addRequired('fs', @(v) isnumeric(v) && isscalar(v) && v > 0);
p.addParameter('BandLow', 0.5, @(v) isscalar(v) && v > 0);
p.addParameter('BandHigh', 40, @(v) isscalar(v) && v > 0);
p.addParameter('FilterOrder', 2, @(v) isscalar(v) && v >= 1 && v == fix(v));
p.addParameter('NotchFrequency', 60, @(v) isscalar(v) && v > 0);
p.addParameter('NotchQ', 35, @(v) isscalar(v) && v > 0);
p.addParameter('BaselineShort', 0.200, @(v) isscalar(v) && v > 0);
p.addParameter('BaselineLong', 0.600, @(v) isscalar(v) && v > 0);
p.addParameter('ApplyNotch', true, @(v) islogical(v) && isscalar(v));
p.parse(x, fs, varargin{:});
opt = p.Results;

wasRow = isrow(x);
signal = double(x(:));
nyquist = fs / 2;

if opt.BandHigh >= nyquist
    error('preprocessEcg:aboveNyquist', ...
        'Upper passband edge %g Hz must be below Nyquist (%g Hz)', ...
        opt.BandHigh, nyquist);
end
if opt.BandLow >= opt.BandHigh
    error('preprocessEcg:badBand', ...
        'Lower passband edge %g Hz must be below the upper edge %g Hz', ...
        opt.BandLow, opt.BandHigh);
end

% ---------------------------------------------------------------------
% Stage 1: baseline wander removal by cascaded moving medians
% ---------------------------------------------------------------------
shortWindow = localOddWindow(opt.BaselineShort, fs);
longWindow  = localOddWindow(opt.BaselineLong, fs);

if numel(signal) < longWindow
    error('preprocessEcg:signalTooShort', ...
        ['Signal has %d samples but the baseline stage needs at least %d ' ...
         '(%g s at %g Hz)'], numel(signal), longWindow, opt.BaselineLong, fs);
end

baseline = movmedian(movmedian(signal, shortWindow), longWindow);
detrended = signal - baseline;

% ---------------------------------------------------------------------
% Stage 2: zero-phase Butterworth bandpass
% ---------------------------------------------------------------------
[bBand, aBand] = butter(opt.FilterOrder, ...
    [opt.BandLow, opt.BandHigh] / nyquist, 'bandpass');
banded = filtfilt(bBand, aBand, detrended);

% ---------------------------------------------------------------------
% Stage 3: powerline notch
% ---------------------------------------------------------------------
if opt.ApplyNotch && opt.NotchFrequency < nyquist
    [bNotch, aNotch] = notchBiquad(opt.NotchFrequency, fs, opt.NotchQ);
    clean = filtfilt(bNotch, aNotch, banded);
else
    bNotch = 1;
    aNotch = 1;
    clean = banded;
end

info.baseline  = localMatchShape(baseline, wasRow);
info.detrended = localMatchShape(detrended, wasRow);
info.banded    = localMatchShape(banded, wasRow);
info.clean     = localMatchShape(clean, wasRow);
info.bandpass  = struct('b', bBand, 'a', aBand);
info.notch     = struct('b', bNotch, 'a', aNotch);
info.settings  = struct( ...
    'samplingFrequency',   fs, ...
    'bandLow',             opt.BandLow, ...
    'bandHigh',            opt.BandHigh, ...
    'filterOrder',         opt.FilterOrder, ...
    'notchFrequency',      opt.NotchFrequency, ...
    'notchQ',              opt.NotchQ, ...
    'notchApplied',        opt.ApplyNotch && opt.NotchFrequency < nyquist, ...
    'baselineShortWindow', shortWindow, ...
    'baselineLongWindow',  longWindow);

clean = info.clean;
end


% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------
function n = localOddWindow(seconds, fs)
%LOCALODDWINDOW  Window length in samples, forced odd so it stays centred.
n = round(seconds * fs);
if n < 1
    n = 1;
end
if mod(n, 2) == 0
    n = n + 1;
end
end


function y = localMatchShape(v, wasRow)
if wasRow
    y = v(:).';
else
    y = v(:);
end
end
