function tvm_freesurferBoundariesToVolume(configuration)
% TVM_FREESURFERBOUNDARIESTOVOLUME
%   TVM_FREESURFERBOUNDARIESTOVOLUME(configuration)
%   @todo Add description
%
% Input:
%   i_SubjectDirectory
%   i_RegistrationVolume
%   i_FreeSurferFolder
% Output:
%   o_Boundaries
%

%   Copyright (C) Tim van Mourik, 2014, DCCN
%
% This file is part of the fmri analysis toolbox, see 
% https://github.com/TimVanMourik/FmriAnalysis for the documentation and 
% details.
%
%    This toolbox is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    This toolbox is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with the fmri analysis toolbox. If not, see 
%    <http://www.gnu.org/licenses/>.

%% Parse configuration
subjectDirectory        = tvm_getOption(configuration, 'i_SubjectDirectory', pwd());
    % default: current working directory
referenceFile           = fullfile(subjectDirectory, tvm_getOption(configuration, 'i_RegistrationVolume'));
    %no default
freeSurferName          = tvm_getOption(configuration, 'i_FreeSurferFolder', 'FreeSurfer');
    %[subjectDirectory, 'FreeSurfer']
boundariesFile          = fullfile(subjectDirectory, tvm_getOption(configuration, 'o_Boundaries'));
    %no default
    
%%
freeSurferFolder = fullfile(subjectDirectory, freeSurferName);

if ~exist(fullfile(freeSurferFolder, 'mri/brain.nii'), 'file')
    unix(['mri_convert ' fullfile(freeSurferFolder, 'mri/brain.mgz') ' ' fullfile(freeSurferFolder, 'mri/brain.nii') ' ;']);
end

surfaceFolder = fullfile(freeSurferFolder, 'surf');
convertToAscii(fullfile(surfaceFolder, 'rh.white'));
convertToAscii(fullfile(surfaceFolder, 'rh.pial'));
convertToAscii(fullfile(surfaceFolder, 'lh.white'));
convertToAscii(fullfile(surfaceFolder, 'lh.pial'));

%% Load the volume data
functionalScan          = spm_vol(referenceFile);
functionalScan          = functionalScan(1);
structuralScan          = spm_vol(fullfile(freeSurferFolder, 'mri/brain.nii'));
functionalScan.volume   = spm_read_vols(functionalScan);
structuralScan.volume   = spm_read_vols(structuralScan);

voxelDimensionsFunctional = sqrt(sum(functionalScan.mat(:, 1:3) .^ 2));
voxelDimensionsStructural = sqrt(sum(structuralScan.mat(:, 1:3) .^ 2));

% load boundaries
loadedBoundaryInformation = [];
loadedBoundaryInformation.SurfaceWhite = fullfile(freeSurferFolder, 'surf/?h.white.asc');
loadedBoundaryInformation.SurfacePial  = fullfile(freeSurferFolder, 'surf/?h.pial.asc');

surfaceData = tvm_loadFreeSurferAsciiFile(loadedBoundaryInformation);
wSurface = surfaceData.SurfaceWhite;
pSurface = surfaceData.SurfacePial;
faceData = surfaceData.Faces; %#ok<NASGU>

%%
freeSurferMatrixFunctional = tvm_dimensionsToFreesurferMatrix(voxelDimensionsFunctional, functionalScan.dim);
freeSurferMatrixStructural = tvm_dimensionsToFreesurferMatrix(voxelDimensionsStructural, structuralScan.dim);
                    
shiftByOne = [  1, 0, 0, 1; 
                0, 1, 0, 1; 
                0, 0, 1, 1; 
                0, 0, 0, 1];

%%
for hemisphere = 1:2
    wSurface{hemisphere} = wSurface{hemisphere} * inv(freeSurferMatrixStructural') * shiftByOne' * structuralScan.mat' * eye(4)' * inv(functionalScan.mat)';
    pSurface{hemisphere} = pSurface{hemisphere} * inv(freeSurferMatrixStructural') * shiftByOne' * structuralScan.mat' * eye(4)' * inv(functionalScan.mat)';
end

%%
save(boundariesFile, 'wSurface', 'pSurface', 'faceData');

end %end function


function convertToAscii(fileName)
asciiFile = [fileName '.asc'];

if ~exist(asciiFile, 'file')
    unix(['mris_convert ' fileName ' ' asciiFile ';']);
end

end %end function


function test %#ok<DEFNU>
%% reverse transformation
for hemisphere = 1:2
    wSurface{hemisphere} = wSurface{hemisphere} / t; %#ok<AGROW>
    pSurface{hemisphere} = pSurface{hemisphere} / t; %#ok<AGROW>
end
%%
slice = functionalScan.dim(1) / 2;
showSlice(functionalScan.volume,  slice, wSurface, pSurface, 'sagittal');
slice = functionalScan.dim(2) / 2;
showSlice(functionalScan.volume,  slice, wSurface, pSurface, 'coronal');
slice = functionalScan.dim(3) / 2;
showSlice(functionalScan.volume,  slice, wSurface, pSurface, 'horizontal');

%%
slice = structuralScan.dim(1) / 2;
showSlice(structuralScan.volume,  slice, wSurface, pSurface, 'sagittal');
slice = structuralScan.dim(2) / 2;
showSlice(structuralScan.volume,  slice, wSurface, pSurface, 'coronal');
slice = structuralScan.dim(3) / 2;
showSlice(structuralScan.volume,  slice, wSurface, pSurface, 'horizontal');
end

% freeSurferIdentityRegistration = inv(freeSurferMatrixStructural)' * shiftByOne' * structuralScan.mat' * inv(functionalScan.mat)' * inv(shiftByOne)' * freeSurferMatrixFunctional';
% perfect structural match:
% t = inv(freeSurferMatrixStructural)' * shiftByHalf';
% functional match without registration
% t = inv(freeSurferMatrixStructural)' * shiftByOne' * structuralScan.mat' * inv(functionalScan.mat)' * inv(shiftByOne)' * shiftByHalf'; 
% identical to the previous line
% t = freeSurferIdentityRegistration * inv(freeSurferMatrixFunctional)' * shiftByHalf'; 


% ?coregistrationMatrix = inv(functionalScan.mat) * inv(shiftByOne) * freeSurferMatrixFunctional * bbrCoregistrationMatrix * inv(freeSurferMatrixStructural) * shiftByOne * structuralScan.mat; %#ok<NASGU>
% ?coregistrationMatrix = inv(structuralScan.mat) * inv(shiftByOne) * freeSurferMatrixStructural * bbrCoregistrationMatrix * inv(freeSurferMatrixFunctional) * shiftByOne * functionalScan.mat; %#ok<NASGU>
% Cfs = bbrCoregistrationMatrix' * inv(freeSurferMatrixFunctional') * shiftByOne' * functionalScan.mat' * inv(structuralScan.mat)' * inv(shiftByOne)' * freeSurferMatrixStructural';
% coregistrationMatrix = inv(structuralScan.mat)' * inv(shiftByOne)' * freeSurferMatrixStructural' * bbrCoregistrationMatrix' * inv(freeSurferMatrixFunctional') * shiftByOne' * functionalScan.mat';
% coregistrationMatrix = inv(coregistrationMatrix);
% coregistrationMatrix = (freeSurferIdentityRegistration \ bbrCoregistrationMatrix')';
% t = inv(freeSurferMatrixStructural)' * inv(shiftByOne)' * inv(structuralScan.mat)' * functionalScan.mat' * shiftByOne' * inv(freeSurferMatrixFunctional)' * coregistrationMatrix' * freeSurferMatrixStructural';

