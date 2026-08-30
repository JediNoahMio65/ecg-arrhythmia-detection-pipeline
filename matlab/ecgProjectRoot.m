function root = ecgProjectRoot()
%ECGPROJECTROOT  Absolute path to the repository root.
%
%   ROOT = ECGPROJECTROOT() returns the directory that contains cpp, matlab
%   and data. It is derived from the location of this file, so scripts and
%   tests locate the record files and the C++ fixture without depending on
%   the current working directory.
%
%   This file lives in <root>/matlab, so the root is one level up.

matlabDir = fileparts(mfilename('fullpath'));
root = fileparts(matlabDir);
end
