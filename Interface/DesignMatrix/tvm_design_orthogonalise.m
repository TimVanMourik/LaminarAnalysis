function tvm_design_orthogonalise(configuration)
% TVM_DESIGN_ORTHOGONALISE
%   TVM_DESIGN_ORTHOGONALISE(configuration)
%   @todo Add description
%
% Input:
%   i_SubjectDirectory
%   i_DesignMatrix
%   i_Order
% Output:
%   o_DesignMatrix

%   Copyright (C) Tim van Mourik, 2015-2016, DCCN
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
designFileIn            = fullfile(subjectDirectory, tvm_getOption(configuration, 'i_DesignMatrix'));
    %no default
regressorsLabels        = tvm_getOption(configuration, 'i_Order');
    %no default
designFileOut           = fullfile(subjectDirectory, tvm_getOption(configuration, 'o_DesignMatrix'));
    %no default
    
definitions = tvm_definitions();

%%
load(designFileIn, definitions.GlmDesign);

for i = 1:length(regressorsLabels)
    regressorsOfInterest = cellfun(@strfind, repmat({design.RegressorLabel}, [1, length(regressorsLabels{i})]), regressorsLabels{i}, 'UniformOutput', false);
    regressorsOfInterest = mod(find(~cellfun(@isempty, [regressorsOfInterest{:}])), length(design.RegressorLabel));
    regressorsOfInterest(regressorsOfInterest == 0) = size(design.DesignMatrix, 2);
    design.DesignMatrix(:, regressorsOfInterest) = spm_orth(design.DesignMatrix(:, regressorsOfInterest));
end
save(designFileOut, definitions.GlmDesign);


end %end function











