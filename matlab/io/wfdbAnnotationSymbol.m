function out = wfdbAnnotationSymbol(code)
%WFDBANNOTATIONSYMBOL  Printable symbol for one or more WFDB type codes.
%
%   S = WFDBANNOTATIONSYMBOL(CODE) returns the printable symbol for a scalar
%   CODE as a character vector, or a cell array of character vectors when
%   CODE is an array. Codes outside the table, and codes with no assigned
%   meaning, return an empty character vector.
%
%   Example:
%       wfdbAnnotationSymbol(5)   % 'V'
%       wfdbAnnotationSymbol(28)  % '+'

tbl = wfdbCodeTable();
nCodes = numel(tbl.symbol);

out = cell(size(code));
for k = 1:numel(code)
    c = double(code(k));
    if c >= 0 && c <= nCodes - 1 && c == fix(c)
        out{k} = tbl.symbol{c + 1};
    else
        out{k} = '';
    end
end

if isscalar(code)
    out = out{1};
end
end
