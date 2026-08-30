function [physical, raw] = readWfdbSignal(dataPath, hdr, varargin)
%READWFDBSIGNAL  Decode a WFDB format-212 signal file.
%
%   [PHYSICAL, RAW] = READWFDBSIGNAL(DATAPATH, HDR) reads the samples in
%   DATAPATH using the layout declared by the header struct HDR (see
%   READWFDBHEADER). RAW is an HDR.numSamples-by-HDR.numSignals matrix of
%   signed integer ADC values. PHYSICAL is the same matrix converted to
%   physical units, normally millivolts:
%
%       physical = (raw - baseline) / adcGain
%
%   [PHYSICAL, RAW] = READWFDBSIGNAL(..., 'MaxSamples', N) stops after N
%   samples per signal, which is useful for quick interactive work on a long
%   record.
%
%   Format 212 packs two successive 12-bit two's-complement values into three
%   bytes:
%
%       byte0   low 8 bits of the first value
%       byte1   low nibble  = high 4 bits of the first value
%               high nibble = high 4 bits of the second value
%       byte2   low 8 bits of the second value
%
%   so
%       first  = byte0 + 256 * (byte1 mod 16)
%       second = byte2 + 256 * floor(byte1 / 16)
%
%   Each 12-bit result is then sign-extended: values at or above 2048 are
%   negative and have 4096 subtracted. Forgetting that step is the classic
%   format-212 bug, and it silently turns every negative deflection into a
%   large positive one.
%
%   Values are stored interleaved across signals, so the packed stream runs
%   signal1(1), signal2(1), signal1(2), signal2(2), and so on.
%
%   This is the MATLAB counterpart of cpp/src/signal_reader.cpp and produces
%   identical raw values for the same file.
%
%   Reference: WFDB Applications Guide, signal file formats.
%   https://physionet.org/physiotools/wag/signal-5.htm

p = inputParser;
p.addParameter('MaxSamples', Inf, @(v) isnumeric(v) && isscalar(v) && v > 0);
p.parse(varargin{:});
maxSamples = p.Results.MaxSamples;

if exist(dataPath, 'file') ~= 2
    error('readWfdbSignal:fileNotFound', ...
        'Signal file not found: %s', dataPath);
end

nSig = hdr.numSignals;
for k = 1:nSig
    if hdr.signals(k).format ~= 212
        error('readWfdbSignal:unsupportedFormat', ...
            'Signal %d uses format %d; this reader handles format 212 only', ...
            k, hdr.signals(k).format);
    end
end

nSamples = min(hdr.numSamples, floor(maxSamples));
if nSamples < 1
    error('readWfdbSignal:noSamples', ...
        'Header declares no samples to read');
end

totalValues = nSamples * nSig;

% Three bytes hold two values; a lone trailing value still occupies two.
nTriplets = floor(totalValues / 2);
hasOdd = mod(totalValues, 2) == 1;
bytesNeeded = 3 * nTriplets + 2 * hasOdd;

fid = fopen(dataPath, 'rb');
if fid < 0
    error('readWfdbSignal:cannotOpen', 'Could not open %s', dataPath);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, bytesNeeded, 'uint8=>double');
clear cleanup

if numel(bytes) < bytesNeeded
    error('readWfdbSignal:truncated', ...
        ['Signal file holds %d bytes but %d samples across %d signals ' ...
         'need %d'], numel(bytes), nSamples, nSig, bytesNeeded);
end

values = zeros(totalValues, 1);

if nTriplets > 0
    b = reshape(bytes(1:3 * nTriplets), 3, nTriplets).';
    mid = b(:, 2);
    first  = b(:, 1) + 256 * mod(mid, 16);
    second = b(:, 3) + 256 * floor(mid / 16);
    values(1:2:2 * nTriplets) = first;
    values(2:2:2 * nTriplets) = second;
end

if hasOdd
    tail = bytes(3 * nTriplets + 1:3 * nTriplets + 2);
    values(end) = tail(1) + 256 * mod(tail(2), 16);
end

% 12-bit two's-complement sign extension.
negative = values >= 2048;
values(negative) = values(negative) - 4096;

raw = reshape(values, nSig, nSamples).';

physical = zeros(nSamples, nSig);
for k = 1:nSig
    physical(:, k) = (raw(:, k) - hdr.signals(k).baseline) / hdr.signals(k).adcGain;
end
end
