function tvm_design_removeVolumes(configuration)
%   
%
%   Copyright (C) Tim van Mourik, 2015, DCCN
%

%% Parse configuration
subjectDirectory        = tvm_getOption(configuration, 'i_SubjectDirectory', '.');
    %no default
designFileIn            = fullfile(subjectDirectory, tvm_getOption(configuration, 'i_DesignMatrix'));
    %no default
deletions               = tvm_getOption(configuration, 'i_Deletions');
    %no default
designFileOut           = fullfile(subjectDirectory, tvm_getOption(configuration, 'o_DesignMatrix'));
    %no default
    
definitions = tvm_definitions();

%%
load(designFileIn, definitions.GlmDesign);

designMatrix = zeros(design.Length, length([deletions{:}]));
regressorLabels = cell(1, length([deletions{:}]));
for column = 1:length(design.Partitions)
    designMatrix(sub2ind(size(designMatrix), deletions{column}, 1:length(deletions{column}))) = 1;
    regressorLabels{column} = 'Deleted';
end
design.DesignMatrix = [design.DesignMatrix, designMatrix];
design.RegressorLabel = [design.RegressorLabel, regressorLabels];
save(designFileOut, definitions.GlmDesign);

end %end function