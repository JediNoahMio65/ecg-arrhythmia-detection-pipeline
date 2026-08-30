function ann = readWfdbAnnotations(annPath)
%READWFDBANNOTATIONS  Decode a MIT-format WFDB annotation file.
%
%   ANN = READWFDBANNOTATIONS(ANNPATH) returns a table with one row per
%   annotation and these variables:
%
%       sample    sample number the annotation refers to (0-based, as stored)
%       code      WFDB annotation type code
%       symbol    printable symbol, for example 'N' or '+'
%       aami      ANSI/AAMI EC57 beat class: N, S, V, F, Q, or '-'
%       isBeat    true when the annotation marks a QRS complex
%       subtype   annotation subtype, from a SUB modifier word
%       chan      signal channel, from a CHN modifier word
%       num       annotation number, from a NUM modifier word
%       aux       auxiliary payload bytes as a uint8 row vector
%       auxText   the payload as text, with trailing NUL bytes removed
%
%   Format
%   ------
%   Each annotation is a little-endian 16-bit word. The six most significant
%   bits are the type code and the ten least significant bits are the number
%   of samples since the previous annotation:
%
%       code     = floor(word / 1024)
%       interval = mod(word, 1024)
%
%   Codes 59 to 63 are not annotations but structural words that modify the
%   annotation they follow:
%
%       59  SKIP   next two words carry a signed 32-bit sample jump,
%                  high word first, for gaps longer than 1023 samples
%       60  NUM    low byte is a signed annotation number
%       61  SUB    low byte is a signed subtype
%       62  CHN    low byte is an unsigned channel number
%       63  AUX    low ten bits are a byte count; that many bytes of payload
%                  follow, packed two per word and padded to an even count
%
%   Sticky versus per-annotation fields
%   -----------------------------------
%   subtype and aux reset for every annotation. chan and num carry forward
%   until a later modifier word changes them.
%
%   The zero-word trap
%   ------------------
%   A word of zero marks end of file, but it is only end of file when it
%   appears where an annotation is expected. An AUX payload can legitimately
%   contain a zero word, and in MIT-BIH record 100 it does: the first
%   annotation is a rhythm change carrying the auxiliary string "(N", which
%   pads to four bytes and produces the payload words 0x4E28 and 0x0000. A
%   reader that scans for the first zero word instead of consuming AUX by its
%   declared byte count stops after one annotation rather than reading all
%   2274 of them. This function consumes AUX by byte count.
%
%   This is the MATLAB counterpart of cpp/src/annotation.cpp and produces
%   identical output for the same file.
%
%   Reference: WFDB Applications Guide, annotation file format.
%   https://physionet.org/physiotools/wag/annot-5.htm

arguments
    annPath (1, :) char
end

if exist(annPath, 'file') ~= 2
    error('readWfdbAnnotations:fileNotFound', ...
        'Annotation file not found: %s', annPath);
end

fid = fopen(annPath, 'rb');
if fid < 0
    error('readWfdbAnnotations:cannotOpen', 'Could not open %s', annPath);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, 'uint8=>double');
clear cleanup

ann = decodeWfdbAnnotationBytes(bytes);
end
