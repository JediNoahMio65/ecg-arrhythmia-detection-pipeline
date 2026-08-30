classdef tPreprocess < matlab.unittest.TestCase
    %TPREPROCESS  Tests for the reference ECG preprocessing chain.
    %
    %   Run from the repository root with:
    %       runtests('matlab/tests')
    %
    %   The synthetic tests drive the chain with signals whose correct
    %   treatment is known in advance: a constant, a linear drift, and sine
    %   waves placed in the stopbands, the passband, and on the powerline
    %   frequency. Together they pin down the frequency response without
    %   depending on any data file.
    %
    %   The record-100 tests then confirm that the chain does the right thing
    %   to a real ECG, and in particular that it does not move the R peaks.
    %   That last property is the one every later stage depends on: detector
    %   evaluation compares detected peak positions against annotation sample
    %   numbers, so a filter that introduced a time shift would corrupt every
    %   score computed downstream.

    properties (Constant)
        Fs = 360
        TestSeconds = 20
        % Amplitude tolerance for a unit sine passed through the chain.
        PassbandTolerance = 0.02
    end

    properties
        DataDir
        HasData = false
        Signal
        BeatSamples
        Clean
        Info
    end

    methods (TestClassSetup)
        function setUpProject(testCase)
            thisFile = mfilename('fullpath');
            if isempty(thisFile)
                thisFile = which('tPreprocess');
            end
            testsDir = fileparts(thisFile);
            matlabDir = fileparts(testsDir);
            addpath(matlabDir);
            addEcgPaths();

            root = ecgProjectRoot();
            testCase.DataDir = fullfile(root, 'data', 'mitdb');

            headerPath = fullfile(testCase.DataDir, '100.hea');
            dataPath = fullfile(testCase.DataDir, '100.dat');
            annPath = fullfile(testCase.DataDir, '100.atr');

            testCase.HasData = exist(headerPath, 'file') == 2 && ...
                exist(dataPath, 'file') == 2 && ...
                exist(annPath, 'file') == 2;

            if testCase.HasData
                hdr = readWfdbHeader(headerPath);
                physical = readWfdbSignal(dataPath, hdr);
                ann = readWfdbAnnotations(annPath);
                testCase.Signal = physical(:, 1);
                testCase.BeatSamples = ann.sample(ann.isBeat);
                [testCase.Clean, testCase.Info] = ...
                    preprocessEcg(testCase.Signal, hdr.samplingFrequency);
            end
        end
    end

    methods (Access = private)
        function requireData(testCase)
            testCase.assumeTrue(testCase.HasData, sprintf( ...
                ['MIT-BIH record 100 not found in %s. Download 100.hea, ' ...
                 '100.dat and 100.atr from ' ...
                 'https://physionet.org/content/mitdb/1.0.0/'], ...
                testCase.DataDir));
        end

        function y = runChain(testCase, x, varargin)
            y = preprocessEcg(x, testCase.Fs, varargin{:});
        end

        function a = interiorAmplitude(testCase, y)
            %INTERIORAMPLITUDE  Sine amplitude from RMS, skipping the edges.
            guard = round(2 * testCase.Fs);
            core = y(guard + 1:end - guard);
            a = sqrt(2 * mean(core .^ 2));
        end

        function [t, n] = timeVector(testCase)
            n = round(testCase.TestSeconds * testCase.Fs);
            t = (0:n - 1).' / testCase.Fs;
        end
    end

    % =====================================================================
    % Shape, orientation and numerical hygiene
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function outputLengthMatchesInput(testCase)
            [t, n] = testCase.timeVector();
            y = testCase.runChain(sin(2 * pi * 10 * t));
            testCase.verifyEqual(numel(y), n);
        end

        function orientationIsPreserved(testCase)
            [t, ~] = testCase.timeVector();
            column = sin(2 * pi * 10 * t);

            yColumn = testCase.runChain(column);
            testCase.verifyTrue(iscolumn(yColumn), ...
                'a column input must give a column output');

            yRow = testCase.runChain(column.');
            testCase.verifyTrue(isrow(yRow), ...
                'a row input must give a row output');

            testCase.verifyEqual(yRow(:), yColumn, 'AbsTol', 1e-12);
        end

        function outputIsFiniteEverywhere(testCase)
            [t, ~] = testCase.timeVector();
            x = sin(2 * pi * 1.3 * t) + 0.4 * sin(2 * pi * 60 * t) + ...
                0.02 * cos(2 * pi * 0.15 * t);
            y = testCase.runChain(x);
            testCase.verifyFalse(any(isnan(y)), 'output contains NaN');
            testCase.verifyFalse(any(isinf(y)), 'output contains Inf');
        end

        function allZeroInputStaysAllZero(testCase)
            [~, n] = testCase.timeVector();
            y = testCase.runChain(zeros(n, 1));
            testCase.verifyEqual(max(abs(y)), 0);
        end

        function infoStructReportsTheSettingsActuallyUsed(testCase)
            [t, ~] = testCase.timeVector();
            [~, info] = preprocessEcg(sin(2 * pi * 10 * t), testCase.Fs, ...
                'BandLow', 1, 'BandHigh', 30, 'NotchFrequency', 50);
            st = info.settings;
            testCase.verifyEqual(st.samplingFrequency, testCase.Fs);
            testCase.verifyEqual(st.bandLow, 1);
            testCase.verifyEqual(st.bandHigh, 30);
            testCase.verifyEqual(st.notchFrequency, 50);
            testCase.verifyTrue(st.notchApplied);
            % Median windows must be odd so the moving window stays centred.
            testCase.verifyEqual(mod(st.baselineShortWindow, 2), 1);
            testCase.verifyEqual(mod(st.baselineLongWindow, 2), 1);
            testCase.verifyEqual(st.baselineShortWindow, 73);   % 200 ms
            testCase.verifyEqual(st.baselineLongWindow, 217);   % 600 ms
        end

        function intermediateStagesAreReturnedAndConsistent(testCase)
            [t, ~] = testCase.timeVector();
            x = sin(2 * pi * 10 * t) + 0.5;
            [clean, info] = preprocessEcg(x, testCase.Fs);
            testCase.verifyEqual(info.clean, clean);
            testCase.verifyEqual(info.detrended, x - info.baseline, ...
                'AbsTol', 1e-12);
            testCase.verifyEqual(numel(info.baseline), numel(x));
            testCase.verifyEqual(numel(info.banded), numel(x));
        end
    end

    % =====================================================================
    % Baseline removal
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function constantOffsetIsRemovedExactly(testCase)
            [~, n] = testCase.timeVector();
            y = testCase.runChain(5 * ones(n, 1));
            guard = round(2 * testCase.Fs);
            testCase.verifyLessThan(max(abs(y(guard + 1:end - guard))), 1e-9);
        end

        function slowLinearDriftIsRemoved(testCase)
            [~, n] = testCase.timeVector();
            drift = linspace(-2, 2, n).';
            y = testCase.runChain(drift);
            guard = round(2 * testCase.Fs);
            testCase.verifyLessThan(max(abs(y(guard + 1:end - guard))), 0.01);
        end

        function respiratoryBandWanderIsStronglyAttenuated(testCase)
            % 0.1 Hz is a typical respiration rate and must be suppressed.
            [t, ~] = testCase.timeVector();
            y = testCase.runChain(sin(2 * pi * 0.1 * t));
            testCase.verifyLessThan(testCase.interiorAmplitude(y), 0.01);
        end

        function baselineEstimateTracksDriftWithoutEatingTheRPeak(testCase)
            % A tall narrow spike on a slow ramp. The median-based baseline
            % should follow the ramp and ignore the spike, which is exactly
            % why a median is used here instead of a high-pass filter.
            [t, n] = testCase.timeVector();
            ramp = 0.5 * sin(2 * pi * 0.1 * t);
            spikeIndex = round(n / 2);
            x = ramp;
            x(spikeIndex) = x(spikeIndex) + 2;

            [~, info] = preprocessEcg(x, testCase.Fs);

            % The baseline at the spike must stay near the ramp, not rise.
            testCase.verifyLessThan( ...
                abs(info.baseline(spikeIndex) - ramp(spikeIndex)), 0.05);
            % And the spike must survive detrending nearly intact.
            testCase.verifyGreaterThan(info.detrended(spikeIndex), 1.9);
        end
    end

    % =====================================================================
    % Frequency response
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function passbandSinesPassThroughAtNearUnityGain(testCase)
            [t, ~] = testCase.timeVector();
            for f0 = [5, 10]
                y = testCase.runChain(sin(2 * pi * f0 * t));
                testCase.verifyEqual(testCase.interiorAmplitude(y), 1, ...
                    'AbsTol', testCase.PassbandTolerance, ...
                    sprintf('%g Hz should pass at close to unity gain', f0));
            end
            % 20 Hz is still inside the passband but nearer the upper edge.
            y20 = testCase.runChain(sin(2 * pi * 20 * t));
            testCase.verifyGreaterThan(testCase.interiorAmplitude(y20), 0.90);
        end

        function contentWellAboveTheUpperEdgeIsAttenuated(testCase)
            [t, ~] = testCase.timeVector();
            y = testCase.runChain(sin(2 * pi * 80 * t));
            testCase.verifyLessThan(testCase.interiorAmplitude(y), 0.10);
        end

        function powerlineFrequencyIsSuppressedByTheNotch(testCase)
            [t, ~] = testCase.timeVector();
            x = sin(2 * pi * 60 * t);

            withNotch = testCase.interiorAmplitude(testCase.runChain(x));
            withoutNotch = testCase.interiorAmplitude( ...
                testCase.runChain(x, 'ApplyNotch', false));

            testCase.verifyLessThan(withNotch, 0.02, ...
                '60 Hz should be almost entirely removed');
            % The notch must be doing most of the work, not the bandpass.
            testCase.verifyLessThan(withNotch, withoutNotch / 10, ...
                'the notch stage should attenuate 60 Hz by at least tenfold');
        end

        function theNotchIsNarrowEnoughToSpareNearbyContent(testCase)
            % A notch that removed 30 Hz along with 60 Hz would be useless.
            [t, ~] = testCase.timeVector();
            plain = testCase.interiorAmplitude( ...
                testCase.runChain(sin(2 * pi * 30 * t), 'ApplyNotch', false));
            notched = testCase.interiorAmplitude( ...
                testCase.runChain(sin(2 * pi * 30 * t)));
            testCase.verifyEqual(notched, plain, 'RelTol', 0.02);
        end

        function theChainIsZeroPhase(testCase)
            % FILTFILT runs the filter forwards and backwards, so the impulse
            % response must be symmetric about the impulse and peak exactly on
            % it. Any lag here would shift every R peak away from its
            % annotation.
            [~, n] = testCase.timeVector();
            centre = round(n / 2);
            x = zeros(n, 1);
            x(centre) = 1;

            y = testCase.runChain(x);

            [~, peakIndex] = max(abs(y));
            testCase.verifyEqual(peakIndex, centre, ...
                'the impulse response must peak on the impulse itself');

            span = 300;
            forward = y(centre + 1:centre + span);
            backward = y(centre - 1:-1:centre - span);
            testCase.verifyEqual(forward, backward, 'AbsTol', 1e-9, ...
                'the impulse response must be symmetric about the impulse');
        end
    end

    % =====================================================================
    % Argument validation
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function upperEdgeAtOrAboveNyquistIsRejected(testCase)
            [t, ~] = testCase.timeVector();
            testCase.verifyError( ...
                @() preprocessEcg(sin(t), testCase.Fs, 'BandHigh', 180), ...
                'preprocessEcg:aboveNyquist');
        end

        function invertedPassbandIsRejected(testCase)
            [t, ~] = testCase.timeVector();
            testCase.verifyError( ...
                @() preprocessEcg(sin(t), testCase.Fs, ...
                    'BandLow', 40, 'BandHigh', 10), ...
                'preprocessEcg:badBand');
        end

        function signalShorterThanTheBaselineWindowIsRejected(testCase)
            testCase.verifyError( ...
                @() preprocessEcg(ones(50, 1), testCase.Fs), ...
                'preprocessEcg:signalTooShort');
        end

        function notchAtOrAboveNyquistIsRejectedByTheDesigner(testCase)
            testCase.verifyError(@() notchBiquad(200, testCase.Fs, 35), ...
                'notchBiquad:aboveNyquist');
        end
    end

    % =====================================================================
    % Supporting functions
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function notchCoefficientsHaveTheExpectedForm(testCase)
            [b, a] = notchBiquad(60, 360, 35);

            testCase.verifyEqual(a(1), 1, 'AbsTol', 1e-15, ...
                'coefficients must be normalised so a(1) is 1');
            % b is a scaled [1, -2cos(w0), 1], so it is symmetric.
            testCase.verifyEqual(b(1), b(3), 'AbsTol', 1e-15);
            % At 60 Hz with fs 360, w0 is pi/3 and cos(w0) is exactly 0.5,
            % so the middle tap is -1 times the outer taps.
            testCase.verifyEqual(b(2), -b(1), 'AbsTol', 1e-12);

            % The magnitude response must be essentially zero at the notch
            % frequency and close to one an octave away.
            testCase.verifyLessThan( ...
                abs(localResponse(b, a, 60, 360)), 1e-12);
            testCase.verifyEqual( ...
                abs(localResponse(b, a, 30, 360)), 1, 'RelTol', 0.02);
            testCase.verifyEqual( ...
                abs(localResponse(b, a, 120, 360)), 1, 'RelTol', 0.02);
        end

        function aHigherQualityFactorGivesANarrowerNotch(testCase)
            [bWide, aWide] = notchBiquad(60, 360, 5);
            [bNarrow, aNarrow] = notchBiquad(60, 360, 50);
            % Measure 5 Hz away from the notch centre.
            wide = abs(localResponse(bWide, aWide, 55, 360));
            narrow = abs(localResponse(bNarrow, aNarrow, 55, 360));
            testCase.verifyGreaterThan(narrow, wide);
        end

        function bandPowerFractionIsolatesAPureTone(testCase)
            [t, ~] = testCase.timeVector();
            x = sin(2 * pi * 10 * t);
            testCase.verifyEqual(bandPowerFraction(x, testCase.Fs, 9, 11), ...
                1, 'AbsTol', 1e-6);
            testCase.verifyLessThan( ...
                bandPowerFraction(x, testCase.Fs, 0, 5), 1e-6);
        end

        function bandPowerFractionsOverDisjointBandsSumToOne(testCase)
            [t, ~] = testCase.timeVector();
            x = sin(2 * pi * 3 * t) + 0.5 * sin(2 * pi * 25 * t) + ...
                0.2 * sin(2 * pi * 70 * t);
            % The top edge is just above Nyquist so that the final bin is
            % included and the three shares must account for all the power.
            total = bandPowerFraction(x, testCase.Fs, 0, 10) + ...
                bandPowerFraction(x, testCase.Fs, 10, 50) + ...
                bandPowerFraction(x, testCase.Fs, 50, testCase.Fs / 2 + 1);
            testCase.verifyEqual(total, 1, 'AbsTol', 1e-9);
        end

        function bandPowerFractionRejectsAnInvertedBand(testCase)
            testCase.verifyError( ...
                @() bandPowerFraction(ones(100, 1), testCase.Fs, 50, 10), ...
                'bandPowerFraction:badBand');
        end
    end

    % =====================================================================
    % MIT-BIH record 100
    % =====================================================================
    methods (Test, TestTags = {'Record100'})

        function baselineWanderPowerCollapses(testCase)
            testCase.requireData();
            [before, after] = testCase.bandShares(0, 0.5);
            % Roughly 7 percent of the raw signal's power sits below 0.5 Hz.
            testCase.verifyGreaterThan(before, 0.01);
            testCase.verifyLessThan(after, 0.001);
        end

        function powerlinePowerCollapses(testCase)
            testCase.requireData();
            [before, after] = testCase.bandShares(59, 61);
            testCase.verifyLessThan(after, 2e-5);
            testCase.verifyLessThan(after, before / 100);
        end

        function almostAllRemainingPowerSitsInTheDiagnosticBand(testCase)
            testCase.requireData();
            [~, after] = testCase.bandShares(0.5, 40);
            testCase.verifyGreaterThan(after, 0.99);
        end

        function theCleanedSignalIsCentredOnZero(testCase)
            testCase.requireData();
            guard = round(2 * testCase.Fs);
            core = testCase.Clean(guard + 1:end - guard);
            testCase.verifyLessThan(abs(mean(core)), 1e-3);
        end

        function cleaningPreservesTheOverallWaveform(testCase)
            testCase.requireData();
            guard = round(2 * testCase.Fs);
            rawCore = testCase.Signal(guard + 1:end - guard);
            cleanCore = testCase.Clean(guard + 1:end - guard);
            r = localCorrelation(rawCore, cleanCore);
            % High enough to show the ECG is intact, and the shortfall from 1
            % is the baseline wander and mains noise that were removed.
            testCase.verifyGreaterThan(r, 0.90);
        end

        function outputLengthMatchesTheRecord(testCase)
            testCase.requireData();
            testCase.verifyEqual(numel(testCase.Clean), ...
                numel(testCase.Signal));
        end

        function rPeaksStayAlignedWithTheirAnnotations(testCase)
            testCase.requireData();
            [offsets, ~] = testCase.beatPeaks();
            within = mean(abs(offsets) <= 5);
            testCase.verifyGreaterThan(within, 0.99, ...
                'filtering moved too many R peaks away from their annotation');
            testCase.verifyEqual(median(offsets), 0);
        end

        function rPeakAmplitudeSurvivesFiltering(testCase)
            testCase.requireData();
            [~, amplitudes] = testCase.beatPeaks();
            % A steep high-pass would flatten the R peaks; they must stay tall.
            testCase.verifyGreaterThan(mean(amplitudes > 0.3), 0.99);
            testCase.verifyGreaterThan(median(amplitudes), 0.5);
        end
    end

    methods (Access = private)
        function [before, after] = bandShares(testCase, fLow, fHigh)
            guard = round(2 * testCase.Fs);
            rawCore = testCase.Signal(guard + 1:end - guard);
            cleanCore = testCase.Clean(guard + 1:end - guard);
            before = bandPowerFraction(rawCore, testCase.Fs, fLow, fHigh);
            after = bandPowerFraction(cleanCore, testCase.Fs, fLow, fHigh);
        end

        function [offsets, amplitudes] = beatPeaks(testCase)
            guard = round(2 * testCase.Fs);
            searchWindow = round(0.050 * testCase.Fs);
            samples = testCase.BeatSamples;
            samples = samples(samples > guard & ...
                samples < numel(testCase.Signal) - guard);

            offsets = zeros(numel(samples), 1);
            amplitudes = zeros(numel(samples), 1);
            for k = 1:numel(samples)
                % Annotation sample numbers are 0-based.
                centre = samples(k) + 1;
                segment = testCase.Clean( ...
                    centre - searchWindow:centre + searchWindow);
                [amplitudes(k), pos] = max(segment);
                offsets(k) = pos - searchWindow - 1;
            end
        end
    end
end


% =========================================================================
% File-local helpers
% =========================================================================
function h = localResponse(b, a, f, fs)
%LOCALRESPONSE  Complex frequency response of a filter at one frequency.
z = exp(-1i * 2 * pi * f / fs);
powers = (0:max(numel(b), numel(a)) - 1).';
bPadded = zeros(numel(powers), 1);
aPadded = zeros(numel(powers), 1);
bPadded(1:numel(b)) = b(:);
aPadded(1:numel(a)) = a(:);
h = sum(bPadded .* z .^ powers) / sum(aPadded .* z .^ powers);
end


function r = localCorrelation(a, b)
%LOCALCORRELATION  Pearson correlation without Statistics Toolbox.
a = a(:) - mean(a);
b = b(:) - mean(b);
denominator = sqrt(sum(a .^ 2) * sum(b .^ 2));
if denominator == 0
    r = 0;
else
    r = sum(a .* b) / denominator;
end
end
