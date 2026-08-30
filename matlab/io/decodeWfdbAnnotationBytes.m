function ann = decodeWfdbAnnotationBytes(bytes)
%DECODEWFDBANNOTATIONBYTES  Decode annotation bytes already held in memory.
%
%   ANN = DECODEWFDBANNOTATIONBYTES(BYTES) takes a vector of byte values and
%   returns the same table that READWFDBANNOTATIONS returns. Splitting the
%   decoder from the file read makes the word-level logic testable with short
%   hand-built streams, including the SKIP path, which MIT-BIH record 100
%   never exercises.
%
%   See READWFDBANNOTATIONS for the format description.

SKIP = 59;
NUM  = 60;
SUB  = 61;
CHN  = 62;
AUX  = 63;

bytes = double(bytes(:));
nWords = floor(numel(bytes) / 2);

if nWords == 0
    ann = localEmptyTable();
    return
end

words = bytes(1:2:2 * nWords) + 256 * bytes(2:2:2 * nWords);

% One word can produce at most one annotation, so nWords is a safe capacity.
sampleCol  = zeros(nWords, 1);
codeCol    = zeros(nWords, 1);
subtypeCol = zeros(nWords, 1);
chanCol    = zeros(nWords, 1);
numCol     = zeros(nWords, 1);
auxCol     = cell(nWords, 1);

count = 0;
i = 1;
sample = 0;
chan = 0;
num = 0;

while i <= nWords
    word = words(i);
    if word == 0
        break   % End of file, but only here, where an annotation is expected.
    end

    code = floor(word / 1024);
    interval = word - 1024 * code;
    i = i + 1;

    if code == SKIP
        if i + 1 > nWords
            error('decodeWfdbAnnotationBytes:truncatedSkip', ...
                'SKIP word at index %d is missing its two payload words', i - 1);
        end
        % Signed 32-bit jump, high word first.
        jump = words(i) * 65536 + words(i + 1);
        if jump >= 2147483648
            jump = jump - 4294967296;
        end
        sample = sample + jump;
        i = i + 2;
        % A SKIP carries no annotation of its own. The next word is a normal
        % annotation and its interval still adds on top of the jump.
        continue
    end

    sample = sample + interval;

    count = count + 1;
    sampleCol(count)  = sample;
    codeCol(count)    = code;
    subtypeCol(count) = 0;
    chanCol(count)    = chan;
    numCol(count)     = num;
    auxCol{count}     = uint8([]);

    % Consume any modifier words that belong to this annotation.
    while i <= nWords
        modWord = words(i);
        modCode = floor(modWord / 1024);
        lowByte = mod(modWord, 256);

        if modCode == NUM
            num = localSigned8(lowByte);
            numCol(count) = num;
            i = i + 1;
        elseif modCode == SUB
            subtypeCol(count) = localSigned8(lowByte);
            i = i + 1;
        elseif modCode == CHN
            chan = lowByte;
            chanCol(count) = chan;
            i = i + 1;
        elseif modCode == AUX
            byteCount = modWord - 1024 * AUX;
            payloadWords = ceil(byteCount / 2);
            if i + payloadWords > nWords
                error('decodeWfdbAnnotationBytes:truncatedAux', ...
                    ['AUX word at index %d declares %d bytes but the file ' ...
                     'ends first'], i, byteCount);
            end
            pw = words(i + 1:i + payloadWords);
            payload = zeros(1, 2 * payloadWords);
            payload(1:2:end) = mod(pw, 256);
            payload(2:2:end) = floor(pw / 256);
            % Drop the pad byte when the declared count is odd.
            auxCol{count} = uint8(payload(1:byteCount));
            i = i + 1 + payloadWords;
        else
            break
        end
    end
end

sampleCol  = sampleCol(1:count);
codeCol    = codeCol(1:count);
subtypeCol = subtypeCol(1:count);
chanCol    = chanCol(1:count);
numCol     = numCol(1:count);
auxCol     = auxCol(1:count);

if count == 0
    ann = localEmptyTable();
    return
end

symbolCol  = wfdbAnnotationSymbol(codeCol);
aamiCol    = wfdbAamiClass(codeCol);
isBeatCol  = wfdbIsBeatCode(codeCol);

auxTextCol = cell(count, 1);
for k = 1:count
    auxTextCol{k} = localAuxText(auxCol{k});
end

if ~iscell(symbolCol), symbolCol = {symbolCol}; end
if ~iscell(aamiCol),   aamiCol   = {aamiCol};   end

ann = table(sampleCol, codeCol, symbolCol(:), aamiCol(:), isBeatCol(:), ...
    subtypeCol, chanCol, numCol, auxCol, auxTextCol, ...
    'VariableNames', {'sample', 'code', 'symbol', 'aami', 'isBeat', ...
                      'subtype', 'chan', 'num', 'aux', 'auxText'});
end


% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------
function v = localSigned8(b)
%LOCALSIGNED8  Reinterpret a byte as a signed 8-bit value.
if b >= 128
    v = b - 256;
else
    v = b;
end
end


function s = localAuxText(payload)
%LOCALAUXTEXT  Payload bytes as text, with trailing NUL bytes removed.
p = double(payload(:).');
while ~isempty(p) && p(end) == 0
    p(end) = [];
end
s = char(p);
end


function t = localEmptyTable()
t = table(zeros(0, 1), zeros(0, 1), cell(0, 1), cell(0, 1), false(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), cell(0, 1), cell(0, 1), ...
    'VariableNames', {'sample', 'code', 'symbol', 'aami', 'isBeat', ...
                      'subtype', 'chan', 'num', 'aux', 'auxText'});
end
