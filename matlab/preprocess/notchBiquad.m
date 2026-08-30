function [b, a] = notchBiquad(f0, fs, q)
%NOTCHBIQUAD  Second-order IIR notch filter coefficients.
%
%   [B, A] = NOTCHBIQUAD(F0, FS, Q) designs a notch centred on F0 hertz for a
%   signal sampled at FS hertz, with quality factor Q. Higher Q gives a
%   narrower notch that removes less of the surrounding signal.
%
%   The design is the standard analog-prototype biquad notch:
%
%       w0    = 2*pi*F0/FS
%       alpha = sin(w0) / (2*Q)
%       b     = [1, -2*cos(w0), 1]
%       a     = [1 + alpha, -2*cos(w0), 1 - alpha]
%
%   normalised so that a(1) is 1.
%
%   This is written out by hand rather than calling IIRNOTCH because IIRNOTCH
%   ships with DSP System Toolbox, and nothing else in this project needs
%   that toolbox. The coefficients are the same design.

arguments
    f0 (1, 1) double {mustBePositive}
    fs (1, 1) double {mustBePositive}
    q  (1, 1) double {mustBePositive}
end

if f0 >= fs / 2
    error('notchBiquad:aboveNyquist', ...
        'Notch frequency %g Hz must be below Nyquist (%g Hz)', f0, fs / 2);
end

w0 = 2 * pi * f0 / fs;
alpha = sin(w0) / (2 * q);
cosw0 = cos(w0);

b = [1, -2 * cosw0, 1];
a = [1 + alpha, -2 * cosw0, 1 - alpha];

b = b / a(1);
a = a / a(1);
end
