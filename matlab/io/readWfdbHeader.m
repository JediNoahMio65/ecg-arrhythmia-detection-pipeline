function hdr = readWfdbHeader(headerPath)
%READWFDBHEADER  Parse a single-segment WFDB header (.hea) file.
%
%   HDR = READWFDBHEADER(HEADERPATH) returns a struct describing the record:
%
%       recordName          record name from the first line
%       numSignals          number of signals (channels)
%       samplingFrequency   samples per second per signal
%       numSamples          samples per signal
%       durationSeconds     numSamples / samplingFrequency
%       signals             1xN struct array, one entry per signal
%       comments            cell array of the '#' comment lines
%
%   Each element of HDR.signals has the fields fileName, format, adcGain,
%   units, baseline, adcResolution, adcZero, initialValue, checksum,
%   blockSize and description.
%
%   Both LF and CRLF line endings are accepted. MIT-BIH header files use
%   CRLF, so stripping the carriage return matters: leaving it attached turns
%   the final field of each line into something that will not compare equal
%   to the lead name it should hold.
%
%   The gain field has the general shape gain(baseline)/units. A gain of zero
%   marks an uncalibrated signal and is replaced by the WFDB default of 200.
%   When no explicit baseline is given, the ADC zero level defines it.
%
%   This is the MATLAB counterpart of cpp/src/header.cpp and produces the
%   same values for the same file.
%
%   Reference: WFDB Applications Guide, header file format.
%   https://physionet.org/physiotools/wag/header-5.htm

arguments
    headerPath (1, :) char
end

if exist(headerPath, 'file') ~= 2
    error('readWfdbHeader:fileNotFound', ...
        'Header file not found: %s', headerPath);
end

text = fileread(headerPath);
text = strrep(text, sprintf('\r\n'), newline);
text = strrep(text, sprintf('\r'), newline);
rawLines = strsplit(text, newline);

lines = {};
comments = {};
for k = 1:numel(rawLines)
    line = strtrim(rawLines{k});
    if isempty(line)
        continue
    end
    if line(1) == '#'
        comments{end + 1} = strtrim(line(2:end)); %#ok<AGROW>
        continue
    end
    lines{end + 1} = line; %#ok<AGROW>
end

if isempty(lines)
    error('readWfdbHeader:noRecordLine', ...
        'Header file contains no record line: %s', headerPath);
end

% ---------------------------------------------------------------------
% Record line: name numSignals [samplingFrequency [numSamples ...]]
% ---------------------------------------------------------------------
fields = strsplit(lines{1});
if numel(fields) < 2
    error('readWfdbHeader:shortRecordLine', ...
        'Record line needs at least a name and a signal count: %s', lines{1});
end

hdr.recordName = fields{1};
hdr.numSignals = localInteger(fields{2}, 'signal count');
if hdr.numSignals < 1
    error('readWfdbHeader:badSignalCount', ...
        'Signal count must be positive, got %d', hdr.numSignals);
end

% WFDB defaults to 250 Hz when the sampling frequency is omitted.
hdr.samplingFrequency = 250;
if numel(fields) >= 3
    hdr.samplingFrequency = localNumber(fields{3}, 'sampling frequency');
end
if hdr.samplingFrequency <= 0
    error('readWfdbHeader:badSamplingFrequency', ...
        'Sampling frequency must be positive, got %g', hdr.samplingFrequency);
end

hdr.numSamples = 0;
if numel(fields) >= 4
    hdr.numSamples = localInteger(fields{4}, 'sample count');
end

hdr.durationSeconds = hdr.numSamples / hdr.samplingFrequency;

% ---------------------------------------------------------------------
% Signal lines
% ---------------------------------------------------------------------
if numel(lines) < 1 + hdr.numSignals
    error('readWfdbHeader:missingSignalLines', ...
        'Header declares %d signals but describes only %d', ...
        hdr.numSignals, numel(lines) - 1);
end

signals = repmat(localEmptySignal(), 1, hdr.numSignals);
for k = 1:hdr.numSignals
    f = strsplit(lines{1 + k});
    if numel(f) < 2
        error('readWfdbHeader:shortSignalLine', ...
            'Signal line is too short: %s', lines{1 + k});
    end

    s = localEmptySignal();
    s.fileName = f{1};
    s.format = localInteger(f{2}, 'signal format');

    baselinePresent = false;
    if numel(f) >= 3
        [s.adcGain, s.units, s.baseline, baselinePresent] = ...
            localParseGainField(f{3});
    end
    if numel(f) >= 4, s.adcResolution = localInteger(f{4}, 'ADC resolution'); end
    if numel(f) >= 5, s.adcZero       = localInteger(f{5}, 'ADC zero');       end
    if numel(f) >= 6, s.initialValue  = localInteger(f{6}, 'initial value');  end
    if numel(f) >= 7, s.checksum      = localInteger(f{7}, 'checksum');       end
    if numel(f) >= 8, s.blockSize     = localInteger(f{8}, 'block size');     end
    if numel(f) >= 9, s.description   = strjoin(f(9:end), ' ');               end

    % When no explicit baseline is given, the ADC zero level defines it.
    if ~baselinePresent
        s.baseline = s.adcZero;
    end

    signals(k) = s;
end

hdr.signals = signals;
hdr.comments = comments;
end


% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------
function s = localEmptySignal()
s = struct( ...
    'fileName',      '', ...
    'format',        0, ...
    'adcGain',       200, ...
    'units',         'mV', ...
    'baseline',      0, ...
    'adcResolution', 12, ...
    'adcZero',       0, ...
    'initialValue',  0, ...
    'checksum',      0, ...
    'blockSize',     0, ...
    'description',   '');
end


function [gain, units, baseline, baselinePresent] = localParseGainField(token)
%LOCALPARSEGAINFIELD  Split gain(baseline)/units into its three parts.
gain = 200;
units = 'mV';
baseline = 0;
baselinePresent = false;

numText = regexp(token, '^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?', 'match', 'once');
if isempty(numText)
    error('readWfdbHeader:badGain', ...
        'Could not read an ADC gain from: %s', token);
end
gain = str2double(numText);
remainder = token(numel(numText) + 1:end);

if ~isempty(remainder) && remainder(1) == '('
    closing = find(remainder == ')', 1, 'first');
    if isempty(closing)
        error('readWfdbHeader:unterminatedBaseline', ...
            'Unterminated baseline in gain field: %s', token);
    end
    baseline = localInteger(remainder(2:closing - 1), 'signal baseline');
    baselinePresent = true;
    remainder = remainder(closing + 1:end);
end

if ~isempty(remainder) && remainder(1) == '/'
    unitText = remainder(2:end);
    if isempty(unitText)
        error('readWfdbHeader:emptyUnits', ...
            'Empty units in gain field: %s', token);
    end
    units = unitText;
end

if gain < 0
    error('readWfdbHeader:negativeGain', ...
        'ADC gain must not be negative: %s', token);
end
if gain == 0
    gain = 200;  % Uncalibrated signal; WFDB default gain.
end
end


function v = localNumber(text, what)
v = str2double(text);
if isnan(v)
    error('readWfdbHeader:badNumber', ...
        'Could not read a %s from: %s', what, text);
end
end


function v = localInteger(text, what)
v = localNumber(text, what);
if v ~= fix(v)
    error('readWfdbHeader:badInteger', ...
        'Expected an integer %s but got: %s', what, text);
end
end
