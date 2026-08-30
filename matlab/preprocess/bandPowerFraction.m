function frac = bandPowerFraction(x, fs, fLow, fHigh)
%BANDPOWERFRACTION  Share of total signal power falling in a frequency band.
%
%   FRAC = BANDPOWERFRACTION(X, FS, FLOW, FHIGH) returns the fraction of the
%   total power of X that lies in [FLOW, FHIGH) hertz, as a value between 0
%   and 1. The mean is removed first so that the DC term does not dominate.
%
%   This is a plain periodogram rather than a calibrated spectral estimate.
%   It exists to quantify what the preprocessing chain did, for example that
%   the share of power below 0.5 Hz collapses once baseline wander is
%   removed, so a single ratio per band is all that is needed.
%
%   Implemented with FFT alone so that it needs no toolbox.

arguments
    x     (:, 1) double
    fs    (1, 1) double {mustBePositive}
    fLow  (1, 1) double {mustBeNonnegative}
    fHigh (1, 1) double {mustBePositive}
end

if fHigh <= fLow
    error('bandPowerFraction:badBand', ...
        'Upper edge %g Hz must exceed lower edge %g Hz', fHigh, fLow);
end

n = numel(x);
centred = x - mean(x);

spectrum = fft(centred);
half = floor(n / 2) + 1;
power = abs(spectrum(1:half)) .^ 2;

freq = (0:half - 1).' * (fs / n);

total = sum(power);
if total == 0
    frac = 0;
    return
end

inBand = freq >= fLow & freq < fHigh;
frac = sum(power(inBand)) / total;
end
