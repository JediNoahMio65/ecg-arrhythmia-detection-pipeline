function tbl = wfdbCodeTable()
%WFDBCODETABLE  Symbol and description for every WFDB annotation type code.
%
%   TBL = WFDBCODETABLE() returns a struct with two 1x50 cell arrays,
%   TBL.symbol and TBL.description, indexed so that element CODE+1 describes
%   annotation type code CODE. Codes 0 through 49 are the codes that can
%   appear as a real annotation; 50 through 58 are unused and 59 through 63
%   are the structural SKIP, NUM, SUB, CHN and AUX words.
%
%   Entries with an empty symbol are legal codes that carry no predefined
%   meaning. This table is the exact counterpart of kCodeTable in
%   cpp/src/annotation.cpp, so the MATLAB and C++ readers report identical
%   symbols and descriptions for every code.
%
%   Reference: WFDB Applications Guide, annotation codes.
%   https://physionet.org/physiotools/wag/annot-5.htm

persistent cached
if ~isempty(cached)
    tbl = cached;
    return
end

entries = {
    ''  , 'Not an actual annotation'
    'N' , 'Normal beat'
    'L' , 'Left bundle branch block beat'
    'R' , 'Right bundle branch block beat'
    'a' , 'Aberrated atrial premature beat'
    'V' , 'Premature ventricular contraction'
    'F' , 'Fusion of ventricular and normal beat'
    'J' , 'Nodal (junctional) premature beat'
    'A' , 'Atrial premature contraction'
    'S' , 'Premature or ectopic supraventricular beat'
    'E' , 'Ventricular escape beat'
    'j' , 'Nodal (junctional) escape beat'
    '/' , 'Paced beat'
    'Q' , 'Unclassifiable beat'
    '~' , 'Signal quality change'
    ''  , 'Undefined annotation code'
    '|' , 'Isolated QRS-like artifact'
    ''  , 'Undefined annotation code'
    's' , 'ST change'
    'T' , 'T-wave change'
    '*' , 'Systole'
    'D' , 'Diastole'
    '"' , 'Comment annotation'
    '=' , 'Measurement annotation'
    'p' , 'P-wave peak'
    'B' , 'Left or right bundle branch block'
    '^' , 'Non-conducted pacer spike'
    't' , 'T-wave peak'
    '+' , 'Rhythm change'
    'u' , 'U-wave peak'
    '?' , 'Learning'
    '!' , 'Ventricular flutter wave'
    '[' , 'Start of ventricular flutter/fibrillation'
    ']' , 'End of ventricular flutter/fibrillation'
    'e' , 'Atrial escape beat'
    'n' , 'Supraventricular escape beat'
    '@' , 'Link to external data'
    'x' , 'Non-conducted P-wave (blocked APB)'
    'f' , 'Fusion of paced and normal beat'
    '(' , 'Waveform onset'
    ')' , 'Waveform end'
    'r' , 'R-on-T premature ventricular contraction'
    ''  , 'Undefined annotation code'
    ''  , 'Undefined annotation code'
    ''  , 'Undefined annotation code'
    ''  , 'Undefined annotation code'
    ''  , 'Undefined annotation code'
    ''  , 'Undefined annotation code'
    ''  , 'Undefined annotation code'
    ''  , 'Undefined annotation code'
    };

tbl.symbol      = entries(:, 1).';
tbl.description = entries(:, 2).';
cached = tbl;
end
