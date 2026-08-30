function c = wfdbChecksum16(samples)
%WFDBCHECKSUM16  Signed 16-bit checksum of a column of raw ADC values.
%
%   C = WFDBCHECKSUM16(SAMPLES) sums SAMPLES, wraps the total to 16 bits, and
%   reinterprets the result as a signed value in the range -32768 to 32767.
%   This reproduces the checksum that a WFDB header declares for each signal,
%   so comparing it against the declared value verifies that the whole signal
%   file decoded correctly.
%
%   Matches checksum16 in cpp/src/signal_reader.cpp.

total = mod(sum(double(samples(:))), 65536);
if total >= 32768
    total = total - 65536;
end
c = total;
end
