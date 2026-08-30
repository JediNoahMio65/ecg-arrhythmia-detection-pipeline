function out = wfdbAnnotationDescription(code)
%WFDBANNOTATIONDESCRIPTION  Human-readable meaning of a WFDB type code.
%
%   D = WFDBANNOTATIONDESCRIPTION(CODE) returns the description for a scalar
%   CODE as a character vector, or a cell array of character vectors when
%   CODE is an array. Codes outside the table return
%   'Undefined annotation code'.

tbl = wfdbCodeTable();
nCodes = numel(tbl.description);

out = cell(size(code));
for k = 1:numel(code)
    c = double(code(k));
    if c >= 0 && c <= nCodes - 1 && c == fix(c)
        out{k} = tbl.description{c + 1};
    else
        out{k} = 'Undefined annotation code';
    end
end

if isscalar(code)
    out = out{1};
end
end
