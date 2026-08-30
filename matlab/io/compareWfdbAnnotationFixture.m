function result = compareWfdbAnnotationFixture(ann, fixturePath)
%COMPAREWFDBANNOTATIONFIXTURE  Check a decoded table against the C++ fixture.
%
%   RESULT = COMPAREWFDBANNOTATIONFIXTURE(ANN, FIXTUREPATH) compares the
%   annotation table ANN, as returned by READWFDBANNOTATIONS, against the CSV
%   fixture that the C++ test suite uses. RESULT is a struct with fields:
%
%       fixtureRows     number of rows in the fixture
%       decodedRows     height(ANN)
%       mismatches      number of rows that differ in any field
%       firstMismatch   description of the first difference, or ''
%       identical       true when the row counts agree and nothing differs
%
%   The fixture is cpp/tests/data/100.atr.reference.csv, generated from the
%   Python WFDB package by cpp/tests/data/generate_reference.py. Comparing
%   against it means the MATLAB reader is validated against the same external
%   ground truth as the C++ reader, rather than against the C++ reader
%   itself. If both implementations agreed only with each other, a shared
%   misreading of the format would go unnoticed.
%
%   Columns: sample, code, subtype, chan, num, aux_hex.

arguments
    ann table
    fixturePath (1, :) char
end

if exist(fixturePath, 'file') ~= 2
    error('compareWfdbAnnotationFixture:fileNotFound', ...
        'Fixture not found: %s', fixturePath);
end

text = fileread(fixturePath);
text = strrep(text, sprintf('\r\n'), newline);
text = strrep(text, sprintf('\r'), newline);
lines = strsplit(text, newline);

% Drop the header line and any trailing blanks.
rows = {};
for k = 2:numel(lines)
    if ~isempty(strtrim(lines{k}))
        rows{end + 1} = lines{k}; %#ok<AGROW>
    end
end

result.fixtureRows = numel(rows);
result.decodedRows = height(ann);
result.mismatches = 0;
result.firstMismatch = '';

nCompare = min(result.fixtureRows, result.decodedRows);
for k = 1:nCompare
    % strsplit collapses delimiters by default, which would hide the empty
    % trailing aux field, so ask for no collapsing.
    f = strsplit(rows{k}, ',', 'CollapseDelimiters', false);
    if numel(f) < 5
        error('compareWfdbAnnotationFixture:badRow', ...
            'Fixture row %d has %d fields, expected at least 5', k, numel(f));
    end
    if numel(f) >= 6
        auxHex = strtrim(f{6});
    else
        auxHex = '';
    end

    expected = [str2double(f{1}), str2double(f{2}), str2double(f{3}), ...
                str2double(f{4}), str2double(f{5})];
    actual = [ann.sample(k), ann.code(k), ann.subtype(k), ...
              ann.chan(k), ann.num(k)];

    actualHex = localHex(ann.aux{k});

    if ~isequal(expected, actual) || ~strcmp(auxHex, actualHex)
        result.mismatches = result.mismatches + 1;
        if isempty(result.firstMismatch)
            result.firstMismatch = sprintf( ...
                ['row %d: fixture sample=%g code=%g sub=%g chan=%g num=%g ' ...
                 'aux=%s | decoded sample=%g code=%g sub=%g chan=%g num=%g ' ...
                 'aux=%s'], ...
                k, expected(1), expected(2), expected(3), expected(4), ...
                expected(5), auxHex, actual(1), actual(2), actual(3), ...
                actual(4), actual(5), actualHex);
        end
    end
end

result.identical = result.mismatches == 0 && ...
    result.fixtureRows == result.decodedRows;
end


function s = localHex(payload)
%LOCALHEX  Lowercase hex string for a uint8 payload, '' when empty.
if isempty(payload)
    s = '';
    return
end
digits = dec2hex(uint8(payload(:)), 2).';
s = lower(reshape(digits, 1, []));
end
