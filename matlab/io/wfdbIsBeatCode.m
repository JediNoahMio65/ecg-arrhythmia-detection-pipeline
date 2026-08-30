function tf = wfdbIsBeatCode(code)
%WFDBISBEATCODE  True for annotation codes that mark a heartbeat.
%
%   TF = WFDBISBEATCODE(CODE) returns a logical array the same size as CODE.
%   A code is a beat code when it labels a QRS complex rather than a rhythm
%   change, a signal-quality change, or another non-beat event.
%
%   The set below is the 20 codes that the WFDB library treats as QRS
%   annotations, and matches is_beat_code in cpp/src/annotation.cpp:
%
%       N L R a V F J A S E j / Q B ? ! e n f r
%
%   Note that '?' (Learning) and '!' (Ventricular flutter wave) are counted
%   as beats here because WFDB itself does, even though neither is a normal
%   morphological beat label.

beatCodes = [1 2 3 4 5 6 7 8 9 10 11 12 13 25 30 31 34 35 38 41];
tf = ismember(double(code), beatCodes);
end
