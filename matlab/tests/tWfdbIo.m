classdef tWfdbIo < matlab.unittest.TestCase
    %TWFDBIO  Tests for the MATLAB WFDB readers in matlab/io.
    %
    %   Run from the repository root with:
    %       runtests('matlab/tests')
    %
    %   Tests fall into three groups.
    %
    %   Group 1 needs no data files. It covers the annotation code tables and
    %   the word-level decoder, driven by short hand-built byte streams. That
    %   is the only way to exercise the SKIP path, because MIT-BIH record 100
    %   contains no SKIP word.
    %
    %   Group 2 reads MIT-BIH record 100 from data/mitdb. Those tests are
    %   assumption-filtered, so they report as skipped rather than failed when
    %   the gitignored record files are not present.
    %
    %   Group 3 compares the decoded annotations field by field against
    %   cpp/tests/data/100.atr.reference.csv, the fixture the C++ suite uses.
    %   That fixture was generated from the Python WFDB package, so passing it
    %   means the MATLAB and C++ readers are each validated against the same
    %   independent ground truth rather than against one another.

    properties (Constant)
        RecordName = '100'
        % Ground truth for record 100, established independently of this code.
        ExpectedAnnotations = 2274
        ExpectedBeats = 2273
        ExpectedSamplingFrequency = 360
        ExpectedSampleCount = 650000
    end

    properties
        DataDir
        FixturePath
        HasData = false
        Header
        Physical
        Raw
        Ann
    end

    methods (TestClassSetup)
        function setUpProject(testCase)
            thisFile = mfilename('fullpath');
            if isempty(thisFile)
                thisFile = which('tWfdbIo');
            end
            testsDir = fileparts(thisFile);
            matlabDir = fileparts(testsDir);
            addpath(matlabDir);
            addEcgPaths();

            root = ecgProjectRoot();
            testCase.DataDir = fullfile(root, 'data', 'mitdb');
            testCase.FixturePath = fullfile(root, 'cpp', 'tests', 'data', ...
                '100.atr.reference.csv');

            headerPath = fullfile(testCase.DataDir, ...
                [testCase.RecordName '.hea']);
            dataPath = fullfile(testCase.DataDir, ...
                [testCase.RecordName '.dat']);
            annPath = fullfile(testCase.DataDir, ...
                [testCase.RecordName '.atr']);

            testCase.HasData = exist(headerPath, 'file') == 2 && ...
                exist(dataPath, 'file') == 2 && ...
                exist(annPath, 'file') == 2;

            if testCase.HasData
                testCase.Header = readWfdbHeader(headerPath);
                [testCase.Physical, testCase.Raw] = ...
                    readWfdbSignal(dataPath, testCase.Header);
                testCase.Ann = readWfdbAnnotations(annPath);
            end
        end
    end

    methods (Access = private)
        function requireData(testCase)
            testCase.assumeTrue(testCase.HasData, sprintf( ...
                ['MIT-BIH record %s not found in %s. Download 100.hea, ' ...
                 '100.dat and 100.atr from ' ...
                 'https://physionet.org/content/mitdb/1.0.0/'], ...
                testCase.RecordName, testCase.DataDir));
        end
    end

    % =====================================================================
    % Group 1: code tables, no data files needed
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function symbolsMatchTheWfdbTable(testCase)
            testCase.verifyEqual(wfdbAnnotationSymbol(1), 'N');
            testCase.verifyEqual(wfdbAnnotationSymbol(5), 'V');
            testCase.verifyEqual(wfdbAnnotationSymbol(8), 'A');
            testCase.verifyEqual(wfdbAnnotationSymbol(12), '/');
            testCase.verifyEqual(wfdbAnnotationSymbol(28), '+');
            testCase.verifyEqual(wfdbAnnotationSymbol(31), '!');
            testCase.verifyEqual(wfdbAnnotationSymbol(41), 'r');
        end

        function unassignedAndOutOfRangeCodesGiveEmptySymbols(testCase)
            % Codes 15, 17 and 42 onwards are legal but carry no meaning.
            testCase.verifyEqual(wfdbAnnotationSymbol(15), '');
            testCase.verifyEqual(wfdbAnnotationSymbol(17), '');
            testCase.verifyEqual(wfdbAnnotationSymbol(45), '');
            % Outside the table entirely.
            testCase.verifyEqual(wfdbAnnotationSymbol(-1), '');
            testCase.verifyEqual(wfdbAnnotationSymbol(200), '');
        end

        function descriptionsAreNonEmptyForEveryTableEntry(testCase)
            tbl = wfdbCodeTable();
            testCase.verifyEqual(numel(tbl.symbol), 50);
            testCase.verifyEqual(numel(tbl.description), 50);
            for code = 0:49
                testCase.verifyNotEmpty(wfdbAnnotationDescription(code), ...
                    sprintf('code %d has an empty description', code));
            end
            testCase.verifyEqual(wfdbAnnotationDescription(500), ...
                'Undefined annotation code');
        end

        function symbolAndDescriptionVectorise(testCase)
            symbols = wfdbAnnotationSymbol([1, 5, 8]);
            testCase.verifyEqual(symbols, {'N', 'V', 'A'});
            descriptions = wfdbAnnotationDescription([1, 5]);
            testCase.verifyEqual(descriptions, ...
                {'Normal beat', 'Premature ventricular contraction'});
        end

        function beatCodeSetHasExactlyTwentyMembers(testCase)
            isBeat = wfdbIsBeatCode(0:49);
            testCase.verifyEqual(sum(isBeat), 20);
            expected = [1 2 3 4 5 6 7 8 9 10 11 12 13 25 30 31 34 35 38 41];
            testCase.verifyEqual(find(isBeat) - 1, expected);
        end

        function nonBeatCodesAreNotBeats(testCase)
            % Rhythm change, signal quality change, waveform onset and end.
            testCase.verifyFalse(wfdbIsBeatCode(28));
            testCase.verifyFalse(wfdbIsBeatCode(14));
            testCase.verifyFalse(wfdbIsBeatCode(39));
            testCase.verifyFalse(wfdbIsBeatCode(40));
        end

        function aamiMappingFollowsTheDocumentedGrouping(testCase)
            % N: normal, bundle branch block, and the escape beats that the
            % MIT-BIH literature places in N.
            for code = [1 2 3 25 34 11]
                testCase.verifyEqual(wfdbAamiClass(code), 'N', ...
                    sprintf('code %d should map to N', code));
            end
            for code = [8 4 7 9 35]
                testCase.verifyEqual(wfdbAamiClass(code), 'S', ...
                    sprintf('code %d should map to S', code));
            end
            for code = [5 10 41]
                testCase.verifyEqual(wfdbAamiClass(code), 'V', ...
                    sprintf('code %d should map to V', code));
            end
            testCase.verifyEqual(wfdbAamiClass(6), 'F');
            for code = [12 38 13 30 31]
                testCase.verifyEqual(wfdbAamiClass(code), 'Q', ...
                    sprintf('code %d should map to Q', code));
            end
        end

        function everyBeatCodeHasAnAamiClassAndNoOthersDo(testCase)
            for code = 0:49
                cls = wfdbAamiClass(code);
                if wfdbIsBeatCode(code)
                    testCase.verifyNotEqual(cls, '-', sprintf( ...
                        'beat code %d has no AAMI class', code));
                else
                    testCase.verifyEqual(cls, '-', sprintf( ...
                        'non-beat code %d was given AAMI class %s', ...
                        code, cls));
                end
            end
        end

        function checksumWrapsToSignedSixteenBits(testCase)
            testCase.verifyEqual(wfdbChecksum16([1; 2; 3]), 6);
            testCase.verifyEqual(wfdbChecksum16(zeros(10, 1)), 0);
            % 32768 wraps to the most negative 16-bit value.
            testCase.verifyEqual(wfdbChecksum16(32768), -32768);
            testCase.verifyEqual(wfdbChecksum16([32767; 1]), -32768);
            testCase.verifyEqual(wfdbChecksum16(65536), 0);
            testCase.verifyEqual(wfdbChecksum16(-1), -1);
        end
    end

    % =====================================================================
    % Group 1b: the word-level annotation decoder, driven by synthetic bytes
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function emptyInputGivesAnEmptyTable(testCase)
            ann = decodeWfdbAnnotationBytes([]);
            testCase.verifyEqual(height(ann), 0);
            testCase.verifyTrue(istable(ann));
        end

        function aLeadingZeroWordEndsTheFileImmediately(testCase)
            bytes = tWfdbIo.wordsToBytes([0, 1 * 1024 + 50]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(height(ann), 0);
        end

        function intervalsAccumulateIntoAbsoluteSampleNumbers(testCase)
            bytes = tWfdbIo.wordsToBytes( ...
                [1 * 1024 + 100, 1 * 1024 + 50, 1 * 1024 + 25, 0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(ann.sample, [100; 150; 175]);
            testCase.verifyEqual(ann.code, [1; 1; 1]);
        end

        function skipWordCarriesALongSampleJump(testCase)
            % SKIP exists because the ten-bit interval field caps at 1023
            % samples. The two words after it hold a signed 32-bit jump, high
            % word first, and the interval of the following annotation still
            % adds on top of the jump.
            bytes = tWfdbIo.wordsToBytes([ ...
                1 * 1024 + 100, ...        % N at sample 100
                59 * 1024, 0, 5000, ...    % SKIP forward 5000 samples
                1 * 1024 + 10, ...         % N at 100 + 5000 + 10
                0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(height(ann), 2);
            testCase.verifyEqual(ann.sample, [100; 5110]);
        end

        function skipWordHandlesAJumpAboveSixteenBits(testCase)
            % 100000 = 1 * 65536 + 34464, so the high word is non-zero.
            bytes = tWfdbIo.wordsToBytes([ ...
                1 * 1024 + 10, 59 * 1024, 1, 34464, 1 * 1024 + 5, 0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(ann.sample, [10; 100015]);
        end

        function consecutiveSkipWordsAccumulate(testCase)
            bytes = tWfdbIo.wordsToBytes([ ...
                1 * 1024 + 10, ...
                59 * 1024, 0, 1000, ...
                59 * 1024, 0, 2000, ...
                1 * 1024 + 5, 0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(ann.sample, [10; 3015]);
        end

        function auxiliaryPayloadMayContainAZeroWord(testCase)
            % This is the trap that MIT-BIH record 100 sets on the very first
            % annotation. The rhythm string "(N" is three bytes including its
            % terminator, so it pads to four and the second payload word is
            % 0x0000, bit-identical to the end-of-file marker. Consuming AUX
            % by its declared byte count is what keeps the decoder going.
            bytes = tWfdbIo.wordsToBytes([ ...
                28 * 1024 + 18, ...            % '+' at sample 18
                63 * 1024 + 3, 20008, 0, ...   % AUX, 3 bytes: 0x28 0x4E 0x00
                1 * 1024 + 59, ...             % N at sample 77
                0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(height(ann), 2, ...
                'decoder stopped at the zero word inside the AUX payload');
            testCase.verifyEqual(ann.sample, [18; 77]);
            testCase.verifyEqual(ann.aux{1}, uint8([40, 78, 0]));
            testCase.verifyEqual(ann.auxText{1}, '(N');
            testCase.verifyEmpty(ann.aux{2});
        end

        function auxiliaryPayloadWithAnEvenByteCountHasNoPadding(testCase)
            % Four bytes "abcd" occupy exactly two words.
            bytes = tWfdbIo.wordsToBytes([ ...
                28 * 1024 + 5, ...
                63 * 1024 + 4, 25185, 25699, ...  % 'a''b' then 'c''d'
                0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(ann.auxText{1}, 'abcd');
            testCase.verifyEqual(ann.aux{1}, uint8('abcd'));
        end

        function subtypeResetsButChannelAndNumberCarryForward(testCase)
            bytes = tWfdbIo.wordsToBytes([ ...
                1 * 1024 + 10, ...                       % N, defaults
                1 * 1024 + 10, 61 * 1024 + 1, ...        % N with subtype 1
                62 * 1024 + 2, 60 * 1024 + 3, ...        % channel 2, number 3
                1 * 1024 + 10, ...                       % N, subtype back to 0
                0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(height(ann), 3);
            testCase.verifyEqual(ann.subtype, [0; 1; 0], ...
                'subtype must reset for each annotation');
            testCase.verifyEqual(ann.chan, [0; 2; 2], ...
                'channel must carry forward until changed');
            testCase.verifyEqual(ann.num, [0; 3; 3], ...
                'number must carry forward until changed');
        end

        function negativeSubtypeAndNumberAreSignExtended(testCase)
            % SUB and NUM both store a signed byte in the low eight bits.
            bytes = tWfdbIo.wordsToBytes([ ...
                1 * 1024 + 10, 61 * 1024 + 255, 60 * 1024 + 254, 0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(ann.subtype, -1);
            testCase.verifyEqual(ann.num, -2);
        end

        function truncatedSkipAndAuxAreReportedNotIgnored(testCase)
            testCase.verifyError( ...
                @() decodeWfdbAnnotationBytes( ...
                    tWfdbIo.wordsToBytes([59 * 1024, 0])), ...
                'decodeWfdbAnnotationBytes:truncatedSkip');
            testCase.verifyError( ...
                @() decodeWfdbAnnotationBytes( ...
                    tWfdbIo.wordsToBytes([1 * 1024 + 5, 63 * 1024 + 8, 1])), ...
                'decodeWfdbAnnotationBytes:truncatedAux');
        end

        function decodedTableCarriesSymbolClassAndBeatFlag(testCase)
            bytes = tWfdbIo.wordsToBytes( ...
                [1 * 1024 + 10, 8 * 1024 + 10, 5 * 1024 + 10, ...
                 28 * 1024 + 10, 0]);
            ann = decodeWfdbAnnotationBytes(bytes);
            testCase.verifyEqual(ann.symbol, {'N'; 'A'; 'V'; '+'});
            testCase.verifyEqual(ann.aami, {'N'; 'S'; 'V'; '-'});
            testCase.verifyEqual(ann.isBeat, [true; true; true; false]);
        end
    end

    % =====================================================================
    % Group 1c: header parsing on synthetic files
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function missingHeaderFileRaisesAClearError(testCase)
            testCase.verifyError( ...
                @() readWfdbHeader(fullfile(tempdir, 'no_such_record.hea')), ...
                'readWfdbHeader:fileNotFound');
        end

        function gainFieldSplitsIntoGainBaselineAndUnits(testCase)
            path = tWfdbIo.writeTempFile('gain.hea', sprintf([ ...
                'gain 1 250 10\r\n' ...
                'gain.dat 212 500(37)/uV 12 0 0 0 0 LEAD\r\n']));
            hdr = readWfdbHeader(path);
            testCase.verifyEqual(hdr.signals(1).adcGain, 500);
            testCase.verifyEqual(hdr.signals(1).baseline, 37);
            testCase.verifyEqual(hdr.signals(1).units, 'uV');
            testCase.verifyEqual(hdr.signals(1).description, 'LEAD');
        end

        function absentBaselineDefaultsToAdcZero(testCase)
            path = tWfdbIo.writeTempFile('nobase.hea', sprintf([ ...
                'nobase 1 250 10\n' ...
                'nobase.dat 212 200 12 1024 0 0 0 X\n']));
            hdr = readWfdbHeader(path);
            testCase.verifyEqual(hdr.signals(1).baseline, 1024);
        end

        function zeroGainFallsBackToTheWfdbDefault(testCase)
            path = tWfdbIo.writeTempFile('zerogain.hea', sprintf([ ...
                'zerogain 1 250 10\n' ...
                'zerogain.dat 212 0 12 0 0 0 0 X\n']));
            hdr = readWfdbHeader(path);
            testCase.verifyEqual(hdr.signals(1).adcGain, 200);
        end

        function omittedSamplingFrequencyDefaultsToTwoFiftyHertz(testCase)
            path = tWfdbIo.writeTempFile('nofs.hea', sprintf([ ...
                'nofs 1\n' ...
                'nofs.dat 212 200 12 0 0 0 0 X\n']));
            hdr = readWfdbHeader(path);
            testCase.verifyEqual(hdr.samplingFrequency, 250);
        end

        function commentLinesAreCollectedNotParsedAsSignals(testCase)
            path = tWfdbIo.writeTempFile('cmt.hea', sprintf([ ...
                'cmt 1 250 10\n' ...
                '# age 69\n' ...
                'cmt.dat 212 200 12 0 0 0 0 X\n' ...
                '# medication list\n']));
            hdr = readWfdbHeader(path);
            testCase.verifyEqual(hdr.numSignals, 1);
            testCase.verifyEqual(hdr.comments, {'age 69', 'medication list'});
        end

        function headerDeclaringMoreSignalsThanItDescribesIsRejected(testCase)
            path = tWfdbIo.writeTempFile('short.hea', sprintf([ ...
                'short 3 250 10\n' ...
                'short.dat 212 200 12 0 0 0 0 X\n']));
            testCase.verifyError(@() readWfdbHeader(path), ...
                'readWfdbHeader:missingSignalLines');
        end
    end

    % =====================================================================
    % Group 1d: format-212 decoding on a synthetic record
    % =====================================================================
    methods (Test, TestTags = {'NoData'})

        function twelveBitValuesAreSignExtended(testCase)
            % Bytes 255, 15, 1 pack first = 0xFFF and second = 0x001. As
            % twelve-bit two's complement those are -1 and +1. A reader that
            % skips sign extension would report 4095 instead of -1, silently
            % turning every downward deflection into a large upward one.
            folder = tWfdbIo.makeTempFolder();
            headerPath = fullfile(folder, 'sx.hea');
            tWfdbIo.writeTextFile(headerPath, sprintf([ ...
                'sx 1 360 2\n' ...
                'sx.dat 212 200 12 0 -1 0 0 TEST\n']));
            tWfdbIo.writeBytes(fullfile(folder, 'sx.dat'), [255, 15, 1]);

            hdr = readWfdbHeader(headerPath);
            [physical, raw] = readWfdbSignal(fullfile(folder, 'sx.dat'), hdr);

            testCase.verifyEqual(raw, [-1; 1]);
            testCase.verifyEqual(physical, [-0.005; 0.005], 'AbsTol', 1e-12);
            testCase.verifyEqual(raw(1), hdr.signals(1).initialValue);
        end

        function interleavedValuesSplitAcrossSignalsInOrder(testCase)
            % Two signals, two samples each: the packed stream runs
            % s1(1), s2(1), s1(2), s2(2).
            folder = tWfdbIo.makeTempFolder();
            headerPath = fullfile(folder, 'il.hea');
            tWfdbIo.writeTextFile(headerPath, sprintf([ ...
                'il 2 360 2\n' ...
                'il.dat 212 200 12 0 10 0 0 A\n' ...
                'il.dat 212 200 12 0 20 0 0 B\n']));
            % Values 10, 20, 30, 40 packed as two triplets.
            bytes = [10, 0, 20,  30, 0, 40];
            tWfdbIo.writeBytes(fullfile(folder, 'il.dat'), bytes);

            hdr = readWfdbHeader(headerPath);
            [~, raw] = readWfdbSignal(fullfile(folder, 'il.dat'), hdr);

            testCase.verifyEqual(size(raw), [2, 2]);
            testCase.verifyEqual(raw(:, 1), [10; 30]);
            testCase.verifyEqual(raw(:, 2), [20; 40]);
        end

        function anOddNumberOfValuesStillDecodes(testCase)
            % Three values need one full triplet plus two more bytes.
            folder = tWfdbIo.makeTempFolder();
            headerPath = fullfile(folder, 'odd.hea');
            tWfdbIo.writeTextFile(headerPath, sprintf([ ...
                'odd 1 360 3\n' ...
                'odd.dat 212 200 12 0 7 0 0 A\n']));
            tWfdbIo.writeBytes(fullfile(folder, 'odd.dat'), ...
                [7, 0, 8,  9, 0]);

            hdr = readWfdbHeader(headerPath);
            [~, raw] = readWfdbSignal(fullfile(folder, 'odd.dat'), hdr);
            testCase.verifyEqual(raw, [7; 8; 9]);
        end

        function truncatedSignalFileIsReportedNotSilentlyPadded(testCase)
            folder = tWfdbIo.makeTempFolder();
            headerPath = fullfile(folder, 'tr.hea');
            tWfdbIo.writeTextFile(headerPath, sprintf([ ...
                'tr 1 360 100\n' ...
                'tr.dat 212 200 12 0 0 0 0 A\n']));
            tWfdbIo.writeBytes(fullfile(folder, 'tr.dat'), [1, 0, 2]);

            hdr = readWfdbHeader(headerPath);
            testCase.verifyError( ...
                @() readWfdbSignal(fullfile(folder, 'tr.dat'), hdr), ...
                'readWfdbSignal:truncated');
        end

        function nonFormat212SignalsAreRejected(testCase)
            folder = tWfdbIo.makeTempFolder();
            headerPath = fullfile(folder, 'f16.hea');
            tWfdbIo.writeTextFile(headerPath, sprintf([ ...
                'f16 1 360 2\n' ...
                'f16.dat 16 200 12 0 0 0 0 A\n']));
            tWfdbIo.writeBytes(fullfile(folder, 'f16.dat'), [0, 0, 0, 0]);

            hdr = readWfdbHeader(headerPath);
            testCase.verifyError( ...
                @() readWfdbSignal(fullfile(folder, 'f16.dat'), hdr), ...
                'readWfdbSignal:unsupportedFormat');
        end
    end

    % =====================================================================
    % Group 2: MIT-BIH record 100
    % =====================================================================
    methods (Test, TestTags = {'Record100'})

        function headerRecordLineMatchesTheFile(testCase)
            testCase.requireData();
            hdr = testCase.Header;
            testCase.verifyEqual(hdr.recordName, testCase.RecordName);
            testCase.verifyEqual(hdr.numSignals, 2);
            testCase.verifyEqual(hdr.samplingFrequency, ...
                testCase.ExpectedSamplingFrequency);
            testCase.verifyEqual(hdr.numSamples, testCase.ExpectedSampleCount);
            testCase.verifyEqual(hdr.durationSeconds, ...
                650000 / 360, 'AbsTol', 1e-9);
        end

        function headerSignalLinesMatchTheFile(testCase)
            testCase.requireData();
            s = testCase.Header.signals;

            testCase.verifyEqual({s.fileName}, {'100.dat', '100.dat'});
            testCase.verifyEqual([s.format], [212, 212]);
            testCase.verifyEqual([s.adcGain], [200, 200]);
            testCase.verifyEqual([s.adcResolution], [11, 11]);
            testCase.verifyEqual([s.adcZero], [1024, 1024]);
            testCase.verifyEqual([s.initialValue], [995, 1011]);
            testCase.verifyEqual([s.checksum], [-22131, 20052]);
            testCase.verifyEqual([s.blockSize], [0, 0]);
            % No explicit baseline in this header, so it follows adcZero.
            testCase.verifyEqual([s.baseline], [1024, 1024]);
        end

        function carriageReturnsAreStrippedFromLeadNames(testCase)
            testCase.requireData();
            % MIT-BIH headers use CRLF. If the carriage return survives, the
            % lead name becomes 'MLII' plus an invisible character and this
            % comparison fails.
            testCase.verifyEqual(testCase.Header.signals(1).description, 'MLII');
            testCase.verifyEqual(testCase.Header.signals(2).description, 'V5');
        end

        function headerCommentsAreCaptured(testCase)
            testCase.requireData();
            testCase.verifyEqual(numel(testCase.Header.comments), 2);
            testCase.verifyEqual(testCase.Header.comments{1}, '69 M 1085 1629 x1');
        end

        function signalMatrixHasTheDeclaredShape(testCase)
            testCase.requireData();
            testCase.verifyEqual(size(testCase.Raw), ...
                [testCase.ExpectedSampleCount, 2]);
            testCase.verifyEqual(size(testCase.Physical), ...
                [testCase.ExpectedSampleCount, 2]);
        end

        function checksumsMatchTheHeaderForEveryChannel(testCase)
            testCase.requireData();
            % This is the strongest single check on the format-212 decoder:
            % it depends on every sample in the file being read correctly.
            for k = 1:testCase.Header.numSignals
                testCase.verifyEqual( ...
                    wfdbChecksum16(testCase.Raw(:, k)), ...
                    testCase.Header.signals(k).checksum, ...
                    sprintf('checksum mismatch on channel %d', k));
            end
        end

        function initialValuesMatchTheHeaderForEveryChannel(testCase)
            testCase.requireData();
            for k = 1:testCase.Header.numSignals
                testCase.verifyEqual(testCase.Raw(1, k), ...
                    testCase.Header.signals(k).initialValue);
            end
        end

        function physicalConversionAppliesBaselineAndGain(testCase)
            testCase.requireData();
            % (995 - 1024) / 200 and (1011 - 1024) / 200
            testCase.verifyEqual(testCase.Physical(1, 1), -0.145, ...
                'AbsTol', 1e-12);
            testCase.verifyEqual(testCase.Physical(1, 2), -0.065, ...
                'AbsTol', 1e-12);
        end

        function maxSamplesOptionLimitsTheRead(testCase)
            testCase.requireData();
            dataPath = fullfile(testCase.DataDir, ...
                [testCase.RecordName '.dat']);
            [physical, raw] = readWfdbSignal(dataPath, testCase.Header, ...
                'MaxSamples', 1000);
            testCase.verifyEqual(size(raw), [1000, 2]);
            testCase.verifyEqual(size(physical), [1000, 2]);
            % The prefix must agree with the full read.
            testCase.verifyEqual(raw, testCase.Raw(1:1000, :));
        end

        function annotationAndBeatCountsMatchGroundTruth(testCase)
            testCase.requireData();
            testCase.verifyEqual(height(testCase.Ann), ...
                testCase.ExpectedAnnotations);
            testCase.verifyEqual(sum(testCase.Ann.isBeat), ...
                testCase.ExpectedBeats);
        end

        function firstAndLastAnnotationSamplesMatchGroundTruth(testCase)
            testCase.requireData();
            testCase.verifyEqual(testCase.Ann.sample(1:6), ...
                [18; 77; 370; 662; 946; 1231]);
            testCase.verifyEqual(testCase.Ann.sample(end), 649991);
        end

        function annotationSampleNumbersAreNonDecreasing(testCase)
            testCase.requireData();
            testCase.verifyTrue(all(diff(testCase.Ann.sample) >= 0));
            testCase.verifyLessThan(testCase.Ann.sample(end), ...
                testCase.ExpectedSampleCount);
        end

        function recordContainsExactlyFourDistinctAnnotationCodes(testCase)
            testCase.requireData();
            codes = testCase.Ann.code;
            testCase.verifyEqual(sort(unique(codes)).', [1, 5, 8, 28]);
            testCase.verifyEqual(sum(codes == 1), 2239);   % N
            testCase.verifyEqual(sum(codes == 8), 33);     % A
            testCase.verifyEqual(sum(codes == 5), 1);      % V
            testCase.verifyEqual(sum(codes == 28), 1);     % + rhythm change
        end

        function aamiClassCountsMatchGroundTruth(testCase)
            testCase.requireData();
            beats = testCase.Ann(testCase.Ann.isBeat, :);
            testCase.verifyEqual(sum(strcmp(beats.aami, 'N')), 2239);
            testCase.verifyEqual(sum(strcmp(beats.aami, 'S')), 33);
            testCase.verifyEqual(sum(strcmp(beats.aami, 'V')), 1);
            testCase.verifyEqual(sum(strcmp(beats.aami, 'F')), 0);
            testCase.verifyEqual(sum(strcmp(beats.aami, 'Q')), 0);
            % The rhythm change is the only non-beat annotation.
            testCase.verifyEqual(sum(strcmp(testCase.Ann.aami, '-')), 1);
        end

        function theOnlyNonZeroSubtypeBelongsToTheSingleVentricularBeat(testCase)
            testCase.requireData();
            ann = testCase.Ann;
            nonZero = find(ann.subtype ~= 0);
            testCase.verifyEqual(numel(nonZero), 1);
            testCase.verifyEqual(ann.sample(nonZero), 546792);
            testCase.verifyEqual(ann.code(nonZero), 5);
            testCase.verifyEqual(ann.subtype(nonZero), 1);
        end

        function channelAndNumberAreZeroThroughoutThisRecord(testCase)
            testCase.requireData();
            testCase.verifyTrue(all(testCase.Ann.chan == 0));
            testCase.verifyTrue(all(testCase.Ann.num == 0));
        end

        function theFirstAnnotationCarriesTheRhythmStringPastAZeroWord(testCase)
            testCase.requireData();
            ann = testCase.Ann;
            testCase.verifyEqual(ann.code(1), 28);
            testCase.verifyEqual(ann.symbol{1}, '+');
            testCase.verifyEqual(ann.sample(1), 18);
            testCase.verifyEqual(ann.aux{1}, uint8([40, 78, 0]));
            testCase.verifyEqual(ann.auxText{1}, '(N');
            % It is the only annotation in the record with a payload.
            hasAux = ~cellfun(@isempty, ann.aux);
            testCase.verifyEqual(sum(hasAux), 1);
        end

        function rrIntervalStatisticsMatchGroundTruth(testCase)
            testCase.requireData();
            beatSamples = testCase.Ann.sample(testCase.Ann.isBeat);
            rr = diff(beatSamples);

            testCase.verifyEqual(numel(rr), testCase.ExpectedBeats - 1);
            testCase.verifyEqual(min(rr), 188);
            testCase.verifyEqual(max(rr), 407);
            testCase.verifyEqual(sum(rr), 649914);
            testCase.verifyEqual(mean(rr), 286.0536971831, 'AbsTol', 1e-7);
            testCase.verifyTrue(all(rr > 0), ...
                'every RR interval must be strictly positive');

            meanHeartRate = 60 * testCase.ExpectedSamplingFrequency / mean(rr);
            testCase.verifyEqual(meanHeartRate, 75.5102982856, 'AbsTol', 1e-7);
        end
    end

    % =====================================================================
    % Group 3: cross-language verification
    % =====================================================================
    methods (Test, TestTags = {'CrossLanguage'})

        function matlabDecodeMatchesTheCppTestFixtureFieldByField(testCase)
            testCase.requireData();
            testCase.assumeTrue(exist(testCase.FixturePath, 'file') == 2, ...
                sprintf('C++ fixture not found: %s', testCase.FixturePath));

            result = compareWfdbAnnotationFixture(testCase.Ann, ...
                testCase.FixturePath);

            testCase.verifyEqual(result.fixtureRows, ...
                testCase.ExpectedAnnotations);
            testCase.verifyEqual(result.decodedRows, result.fixtureRows, ...
                'MATLAB decoded a different number of annotations');
            testCase.verifyEqual(result.mismatches, 0, result.firstMismatch);
            testCase.verifyTrue(result.identical);
        end
    end

    % =====================================================================
    % Static helpers
    % =====================================================================
    methods (Static, Access = private)

        function bytes = wordsToBytes(words)
            %WORDSTOBYTES  Pack 16-bit words little-endian into bytes.
            words = double(words(:));
            bytes = zeros(2 * numel(words), 1);
            bytes(1:2:end) = mod(words, 256);
            bytes(2:2:end) = floor(words / 256);
        end

        function folder = makeTempFolder()
            folder = tempname;
            mkdir(folder);
        end

        function path = writeTempFile(name, text)
            folder = tWfdbIo.makeTempFolder();
            path = fullfile(folder, name);
            tWfdbIo.writeTextFile(path, text);
        end

        function writeTextFile(path, text)
            fid = fopen(path, 'w');
            if fid < 0
                error('tWfdbIo:cannotWrite', 'Could not write %s', path);
            end
            fwrite(fid, text, 'char');
            fclose(fid);
        end

        function writeBytes(path, bytes)
            fid = fopen(path, 'wb');
            if fid < 0
                error('tWfdbIo:cannotWrite', 'Could not write %s', path);
            end
            fwrite(fid, bytes, 'uint8');
            fclose(fid);
        end
    end
end
