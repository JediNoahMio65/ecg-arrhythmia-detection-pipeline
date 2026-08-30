function addEcgPaths()
%ADDECGPATHS  Put the project's MATLAB function folders on the search path.
%
%   ADDECGPATHS() adds <root>/matlab, <root>/matlab/io and
%   <root>/matlab/preprocess. Call it once per MATLAB session before using
%   any of the readers or the preprocessing chain. It is safe to call more
%   than once.
%
%   The paths are added for this session only. Nothing is saved, so the
%   function leaves no trace in the user's stored MATLAB path.

matlabDir = fileparts(mfilename('fullpath'));

addpath(matlabDir);
addpath(fullfile(matlabDir, 'io'));
addpath(fullfile(matlabDir, 'preprocess'));
end
