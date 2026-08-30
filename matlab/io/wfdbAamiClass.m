function out = wfdbAamiClass(code)
%WFDBAAMICLASS  Map a WFDB annotation code onto its ANSI/AAMI EC57 class.
%
%   C = WFDBAAMICLASS(CODE) returns one of 'N', 'S', 'V', 'F', 'Q' or '-'
%   for a scalar CODE, or a cell array of such labels when CODE is an array.
%   The '-' label means the code is not a heartbeat at all.
%
%   The five classes are:
%       N   Normal or bundle-branch-block beat
%       S   Supraventricular ectopic beat
%       V   Ventricular ectopic beat
%       F   Fusion of ventricular and normal beat
%       Q   Unknown or paced beat
%
%   Grouping used here, identical to aami_class_of in
%   cpp/src/annotation.cpp:
%       N  <-  N L R B e j
%       S  <-  A a J S n
%       V  <-  V E r
%       F  <-  F
%       Q  <-  / f Q ? !
%
%   Two grouping decisions are worth stating plainly, because the standard
%   and the published MIT-BIH literature do not agree on them:
%
%     1. Read literally, EC57 describes class S as covering "an atrial or
%        nodal (junctional) premature or escape beat", which would place the
%        escape beats 'e' and 'j' in S. The MIT-BIH classification
%        literature consistently places them in N instead, and this code
%        follows the literature so that reported per-class accuracy is
%        comparable with published results.
%
%     2. EC57 assigns no class at all to the ventricular flutter wave '!'
%        or to the learning label '?'. Both are grouped into Q here.
%
%   References:
%     ANSI/AAMI EC57 - Testing and reporting performance results of cardiac
%     rhythm and ST segment measurement algorithms.
%     https://mdcpp.com/doc/standard/ANSIAAMIEC57-1998(R)2003.pdf
%
%     Systematic review of MIT-BIH beat grouping practice.
%     https://arxiv.org/html/2503.07276v1

classN = [1 2 3 25 34 11];   % N L R B e j
classS = [8 4 7 9 35];       % A a J S n
classV = [5 10 41];          % V E r
classF = [6];                % F
classQ = [12 38 13 30 31];   % / f Q ? !

out = cell(size(code));
for k = 1:numel(code)
    c = double(code(k));
    if ismember(c, classN)
        out{k} = 'N';
    elseif ismember(c, classS)
        out{k} = 'S';
    elseif ismember(c, classV)
        out{k} = 'V';
    elseif ismember(c, classF)
        out{k} = 'F';
    elseif ismember(c, classQ)
        out{k} = 'Q';
    else
        out{k} = '-';
    end
end

if isscalar(code)
    out = out{1};
end
end
