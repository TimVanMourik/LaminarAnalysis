function tvm_puppetWarpRegistration(configuration, registrationConfiguration)
% TVM_PUPPETWARPREGISTRATION
%   TVM_PUPPETWARPREGISTRATION(configuration)
%   @todo Add description
%
% Input:
%   i_SubjectDirectory
%   i_ReferenceVolume
%   i_Boundaries
%   i_Mask
% Output:
%   o_Boundaries
%

%   Copyright (C) Tim van Mourik, 2014-2016, DCCN
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
referenceFile           = fullfile(subjectDirectory, tvm_getOption(configuration, 'i_ReferenceVolume'));
    %no default
boundariesFileIn        = fullfile(subjectDirectory, tvm_getOption(configuration, 'i_Boundaries'));
    %no default
minSize                 = tvm_getOption(configuration, 'i_MinimumVoxels', 10);
    % default: empty
minVertices             = tvm_getOption(configuration, 'i_MinimumVertices', 500);
    % default: empty
cuboidelements          = tvm_getOption(configuration, 'i_CuboidElements', true);
    % default: empty
alphaLevel              = tvm_getOption(configuration, 'i_NeighbourSmoothing', 0.5);
    % default: empty
maskFile                = tvm_getOption(configuration, 'i_Mask', '');
    % default: empty
boundariesFileOut       = fullfile(subjectDirectory, tvm_getOption(configuration, 'o_Boundaries'));
    %no default

definitions = tvm_definitions();

%% Just loading data
referenceVolume = spm_vol(referenceFile);
referenceVolume.volume = spm_read_vols(referenceVolume);

if isempty(maskFile)
    mask = true(referenceVolume.dim);
else
    maskFile = fullfile(subjectDirectory, maskFile);
    mask = ~~spm_read_vols(spm_vol(maskFile));
end

load(boundariesFileIn, definitions.WhiteMatterSurface, definitions.PialSurface, definitions.FaceData);
wSurface = eval(definitions.WhiteMatterSurface);
pSurface = eval(definitions.PialSurface);
faceData = eval(definitions.FaceData);
insideVolume = [];

for hemisphere = 1:2
    if size(wSurface{hemisphere}, 2) == 3
        wSurface{hemisphere} = [wSurface{hemisphere}, ones(size(wSurface{hemisphere}, 1), 1)]; 
        pSurface{hemisphere} = [pSurface{hemisphere}, ones(size(pSurface{hemisphere}, 1), 1)]; 
    end    
%     insideVolume = [insideVolume; ~any(wSurface{hemisphere}(:, 1:3) < 0 | bsxfun(@gt, wSurface{hemisphere}(:, 1:3), referenceVolume.dim(1:3) - 1), 2)];
end

registereSurfaceW = vertcat(wSurface{:});
registereSurfaceP = vertcat(pSurface{:});
[~, selectedVerticesW] = selectVertices(registereSurfaceW, mask);
[~, selectedVerticesP] = selectVertices(registereSurfaceP, mask);
selectedVertices = selectedVerticesW & selectedVerticesP;
% clear('mask', 'selectedVerticesW', 'selectedVerticesP');

registereSurfaceW = registereSurfaceW(selectedVertices, :);
registereSurfaceP = registereSurfaceP(selectedVertices, :);

%% The real implementation
dimensions = referenceVolume.dim; % .* sqrt(sum(referenceVolume.mat(1:3, 1:3) .^ 2));

%divide the mesh
root                = [];
root.anchorPoints   = [min([registereSurfaceW; registereSurfaceP]) - 2 * eps(); ...
                       max([registereSurfaceW; registereSurfaceP]) + 2 * eps()];
root.anchorPoints   = root.anchorPoints(:, 1:3);
root.vertexIndices  = true(size(registereSurfaceW, 1), 1);
cfg                 = [];
cfg.MinVertices     = minVertices;
cfg.MinSize         = minSize;

%find neighbours in mesh
root            = divideMesh(root, cfg, registereSurfaceW);
[root, anchors] = addNeighbourStructure(root);

for level = 0:floor(log2(max(dimensions) / minSize)) - 1 %per level, as smoothing is per level
    elementsCurrentLevel = elementsLevelN(root, level);
    if isempty(elementsCurrentLevel)
        break;
    end
    [neighbourList, relevantAnchors] = neighbourStructure(elementsCurrentLevel, anchors, cuboidelements);
    deformationVectors = cell(size(relevantAnchors));
    %compute
    for i = 1:length(elementsCurrentLevel)
        % transformation for the whole
        w = registereSurfaceW(elementsCurrentLevel(i).vertexIndices, :);
        p = registereSurfaceP(elementsCurrentLevel(i).vertexIndices, :);
        % % % the next line is the bottleneck of the entire script
        elementsCurrentLevel(i).transformation = optimalTransformation(w, p, referenceVolume.volume, registrationConfiguration);
        % % %
        for j = 1:length(elementsCurrentLevel(i).anchorIndices)
            index = find(relevantAnchors == elementsCurrentLevel(i).anchorIndices(j));
            deformationVectors{index} = [deformationVectors{index}; anchors(elementsCurrentLevel(i).anchorIndices(j), :) * (elementsCurrentLevel(i).transformation - eye(4))];
        end
        
        % transformation for the cuboid elements
        if cuboidelements
            for k = 1:length(elementsCurrentLevel(i).cuboids)

                w = registereSurfaceW(elementsCurrentLevel(i).cuboids(k).vertexIndices, :);
                p = registereSurfaceP(elementsCurrentLevel(i).cuboids(k).vertexIndices, :);
                % % % the next line is the bottleneck of the entire script
                elementsCurrentLevel(i).cuboids(k).transformation = optimalTransformation(w, p, referenceVolume.volume, registrationConfiguration);
                % % %
                for j = 1:length(elementsCurrentLevel(i).cuboids(k).anchorIndices)
                    index = find(relevantAnchors == elementsCurrentLevel(i).cuboids(k).anchorIndices(j));
                    deformationVectors{index} = [deformationVectors{index}; anchors(elementsCurrentLevel(i).cuboids(k).anchorIndices(j), :) * (elementsCurrentLevel(i).cuboids(k).transformation - eye(4))];
                end
            end     
        end
    end
    
    %smooth anchor points
    medianDeformation = cellfun(@median, deformationVectors, num2cell(ones(size(deformationVectors))), 'UniformOutput', false);
    for i = 1:length(relevantAnchors)
        neighbourVector = mean(vertcat(medianDeformation{cell2mat(cellfun(@find, cellfun(@eq, repmat({relevantAnchors}, size(neighbourList{i})), num2cell(neighbourList{i}), 'UniformOutput', false), 'UniformOutput', false))}));
        %overwrite with the median
        deformationVectors{i} = (1 - alphaLevel) * medianDeformation{i} + alphaLevel * neighbourVector;
    end
    anchors(relevantAnchors, :) = anchors(relevantAnchors, :) + cat(1, deformationVectors{:});
    
    %deform mesh
    for i = 1:length(elementsCurrentLevel)
        currentAnchors = anchors(elementsCurrentLevel(i).anchorIndices, :);
        deformations = cat(1, deformationVectors{cell2mat(cellfun(@find, cellfun(@eq, repmat({relevantAnchors}, size(elementsCurrentLevel(i).anchorIndices)), num2cell(elementsCurrentLevel(i).anchorIndices), 'UniformOutput', false), 'UniformOutput', false))});
        centreOfMass = mean(currentAnchors, 1);
        T = eye(4);
        T(4, :) = centreOfMass;
        transformedAnchors = currentAnchors / T;
        M = transformedAnchors \ deformations;
%         M = currentAnchors \ deformations + eye(4);
        registereSurfaceW(elementsCurrentLevel(i).vertexIndices, :) = registereSurfaceW(elementsCurrentLevel(i).vertexIndices, :) + registereSurfaceW(elementsCurrentLevel(i).vertexIndices, :) / T * M;
        registereSurfaceP(elementsCurrentLevel(i).vertexIndices, :) = registereSurfaceP(elementsCurrentLevel(i).vertexIndices, :) + registereSurfaceP(elementsCurrentLevel(i).vertexIndices, :) / T * M;
    end    
end

%% Saving output
w1 = selectedVertices(1:length(wSurface{1}));
wSurface{1}(w1, :) = registereSurfaceW(1:sum(w1), :);
pSurface{1}(w1, :) = registereSurfaceP(1:sum(w1), :);
w2 = selectedVertices((end + 1 - length(wSurface{2})):end);
wSurface{2}(w2, :) = registereSurfaceW(end - sum(w2) + 1:end, :);
pSurface{2}(w2, :) = registereSurfaceP(end - sum(w2) + 1:end, :);
save(boundariesFileOut, definitions.WhiteMatterSurface, definitions.PialSurface, definitions.FaceData);

end %end function


function [neighbourList, relevantAnchors] = neighbourStructure(elements, anchors, withCuboids)

neighbourList = cell(length(anchors), 1);
for i = 1:length(elements)
    neighbourList{elements(i).anchorIndices(1)} = [neighbourList{elements(i).anchorIndices(1)}, elements(i).anchorIndices(2), elements(i).anchorIndices(3), elements(i).anchorIndices(5)];
    neighbourList{elements(i).anchorIndices(2)} = [neighbourList{elements(i).anchorIndices(2)}, elements(i).anchorIndices(1), elements(i).anchorIndices(4), elements(i).anchorIndices(6)];
    neighbourList{elements(i).anchorIndices(3)} = [neighbourList{elements(i).anchorIndices(3)}, elements(i).anchorIndices(1), elements(i).anchorIndices(4), elements(i).anchorIndices(7)];
    neighbourList{elements(i).anchorIndices(4)} = [neighbourList{elements(i).anchorIndices(4)}, elements(i).anchorIndices(2), elements(i).anchorIndices(3), elements(i).anchorIndices(8)];
    neighbourList{elements(i).anchorIndices(5)} = [neighbourList{elements(i).anchorIndices(5)}, elements(i).anchorIndices(1), elements(i).anchorIndices(6), elements(i).anchorIndices(7)];
    neighbourList{elements(i).anchorIndices(6)} = [neighbourList{elements(i).anchorIndices(6)}, elements(i).anchorIndices(2), elements(i).anchorIndices(5), elements(i).anchorIndices(8)];
    neighbourList{elements(i).anchorIndices(7)} = [neighbourList{elements(i).anchorIndices(7)}, elements(i).anchorIndices(3), elements(i).anchorIndices(5), elements(i).anchorIndices(8)];
    neighbourList{elements(i).anchorIndices(8)} = [neighbourList{elements(i).anchorIndices(8)}, elements(i).anchorIndices(4), elements(i).anchorIndices(6), elements(i).anchorIndices(7)];

    if withCuboids
        for j = 1:length(elements(i).cuboids)
            neighbourList{elements(i).cuboids(j).anchorIndices(1)} = [neighbourList{elements(i).cuboids(j).anchorIndices(1)}, elements(i).cuboids(j).anchorIndices(2), elements(i).cuboids(j).anchorIndices(3), elements(i).cuboids(j).anchorIndices(5)];
            neighbourList{elements(i).cuboids(j).anchorIndices(2)} = [neighbourList{elements(i).cuboids(j).anchorIndices(2)}, elements(i).cuboids(j).anchorIndices(1), elements(i).cuboids(j).anchorIndices(4), elements(i).cuboids(j).anchorIndices(6)];
            neighbourList{elements(i).cuboids(j).anchorIndices(3)} = [neighbourList{elements(i).cuboids(j).anchorIndices(3)}, elements(i).cuboids(j).anchorIndices(1), elements(i).cuboids(j).anchorIndices(4), elements(i).cuboids(j).anchorIndices(7)];
            neighbourList{elements(i).cuboids(j).anchorIndices(4)} = [neighbourList{elements(i).cuboids(j).anchorIndices(4)}, elements(i).cuboids(j).anchorIndices(2), elements(i).cuboids(j).anchorIndices(3), elements(i).cuboids(j).anchorIndices(8)];
            neighbourList{elements(i).cuboids(j).anchorIndices(5)} = [neighbourList{elements(i).cuboids(j).anchorIndices(5)}, elements(i).cuboids(j).anchorIndices(1), elements(i).cuboids(j).anchorIndices(6), elements(i).cuboids(j).anchorIndices(7)];
            neighbourList{elements(i).cuboids(j).anchorIndices(6)} = [neighbourList{elements(i).cuboids(j).anchorIndices(6)}, elements(i).cuboids(j).anchorIndices(2), elements(i).cuboids(j).anchorIndices(5), elements(i).cuboids(j).anchorIndices(8)];
            neighbourList{elements(i).cuboids(j).anchorIndices(7)} = [neighbourList{elements(i).cuboids(j).anchorIndices(7)}, elements(i).cuboids(j).anchorIndices(3), elements(i).cuboids(j).anchorIndices(5), elements(i).cuboids(j).anchorIndices(8)];
            neighbourList{elements(i).cuboids(j).anchorIndices(8)} = [neighbourList{elements(i).cuboids(j).anchorIndices(8)}, elements(i).cuboids(j).anchorIndices(4), elements(i).cuboids(j).anchorIndices(6), elements(i).cuboids(j).anchorIndices(7)];
        end
    end
end

relevantAnchors = find(~cellfun(@isempty, neighbourList));
neighbourList = neighbourList(relevantAnchors);
neighbourList = cellfun(@unique, neighbourList, 'UniformOutput', false);

end %end function


function root = divideMesh(root, cfg, coordinates)

anchorPoints = cellfun(@colon, ...
                       num2cell( root.anchorPoints(1, :)), ...
                       num2cell((root.anchorPoints(2, :) - root.anchorPoints(1, :)) / 2), ...
                       num2cell( root.anchorPoints(2, :)), ...
                       'UniformOutput', false);

%%
root.cuboids = [];
for d = 1:3    
    boxSize = [1, 1, 1];
    boxSize(d) = 2;    
    [xi, yi, zi] = meshgrid(1:boxSize(1), 1:boxSize(2), 1:boxSize(3));
    cuboidAnchors = cellfun(@(a)a([1,3]), anchorPoints, 'UniformOutput', false);
    cuboidAnchors{d} = anchorPoints{d};
    boundaries = permute(cat(3, ...
        [cuboidAnchors{1}(xi(:)); ...
        cuboidAnchors{1}(xi(:) + 1)], ...
        [cuboidAnchors{2}(yi(:)); ...
        cuboidAnchors{2}(yi(:) + 1)], ...
        [cuboidAnchors{3}(zi(:)); ...
        cuboidAnchors{3}(zi(:) + 1)]), [1, 3, 2]);
    newBoxDimensions = boundaries(2, :, 1) - boundaries(1, :, 1);

    xi = sum(bsxfun(@gt, coordinates(root.vertexIndices, 1), cuboidAnchors{1}), 2);
    yi = sum(bsxfun(@gt, coordinates(root.vertexIndices, 2), cuboidAnchors{2}), 2);
    zi = sum(bsxfun(@gt, coordinates(root.vertexIndices, 3), cuboidAnchors{3}), 2);
    
    ind = sub2ind(boxSize([2, 1, 3]), yi, xi, zi);
    categories = cellfun(@find, ...
                    cellfun(@eq, ...
                        repmat({ind}, [1, prod(boxSize)]), ...
                        num2cell(1:prod(boxSize)), ...
                        'UniformOutput', false), ...
                    'UniformOutput', false);

    validCategories = cellfun(@length, categories) >= cfg.MinVertices;
    categories = categories(validCategories);
    boxBoundaries = boundaries(:, :, validCategories);
    if isempty(categories)
        root.cuboids = [];
        continue;
    end
    categories = cellfun(@(a,b) a(b), repmat({find(root.vertexIndices)}, size(categories)), categories, 'UniformOutput', false);
    newVertices = repmat({false(size(root.vertexIndices))}, size(categories));
    newVertices = cellfun(@(a,b)(ismember(1:length(a), b)), newVertices, categories, 'UniformOutput', false);
    cuboidAnchors = {num2cell(boxBoundaries, [1,2])};

    cuboids = cell(size(categories));
    cuboids = cellfun(@setfield, cuboids, repmat({'vertexIndices'}, size(categories)), newVertices);
    cuboids = cellfun(@setfield, num2cell(cuboids), repmat({'anchorPoints'}, size(categories)), squeeze(cuboidAnchors{:})', 'UniformOutput', false);
    root.cuboids = [root.cuboids, cuboids{:}];
end     
                  
%%              
[xi, yi, zi] = meshgrid([1, 2], [1, 2], [1, 2]);
boundaries = permute(cat(3, ...
    [anchorPoints{1}(xi(:)); ...
    anchorPoints{1}(xi(:) + 1)], ...
    [anchorPoints{2}(yi(:)); ...
    anchorPoints{2}(yi(:) + 1)], ...
    [anchorPoints{3}(zi(:)); ...
    anchorPoints{3}(zi(:) + 1)]), [1, 3, 2]);
newBoxDimensions = boundaries(2, :, 1) - boundaries(1, :, 1);
if any(newBoxDimensions < cfg.MinSize);
    root.children = {};
    return;
end

xi = sum(bsxfun(@gt, coordinates(root.vertexIndices, 1), anchorPoints{1}), 2);
yi = sum(bsxfun(@gt, coordinates(root.vertexIndices, 2), anchorPoints{2}), 2);
zi = sum(bsxfun(@gt, coordinates(root.vertexIndices, 3), anchorPoints{3}), 2);
boxSize = [2, 2, 2];

ind = sub2ind(boxSize([2, 1, 3]), yi, xi, zi);
categories = cellfun(@find, ...
                cellfun(@eq, ...
                    repmat({ind}, [1, prod(boxSize)]), ...
                    num2cell(1:prod(boxSize)), ...
                    'UniformOutput', false), ...
                'UniformOutput', false);
            
validCategories = cellfun(@length, categories) >= cfg.MinVertices;
categories = categories(validCategories);
boundaries = boundaries(:, :, validCategories);
if isempty(categories)
    root.children = {};
    return;
end
categories = cellfun(@(a,b) a(b), repmat({find(root.vertexIndices)}, size(categories)), categories, 'UniformOutput', false);
newVertices = repmat({false(size(root.vertexIndices))}, size(categories));
newVertices = cellfun(@(a,b)(ismember(1:length(a), b)), newVertices, categories, 'UniformOutput', false);
newAnchorPoints = {num2cell(boundaries, [1,2])};

children = cell(size(categories));
children = cellfun(@setfield, children, repmat({'vertexIndices'}, size(categories)), newVertices);
children = cellfun(@setfield, num2cell(children), repmat({'anchorPoints'}, size(categories)), squeeze(newAnchorPoints{:})');

root.children = children;
root.children = cellfun(@divideMesh, num2cell(root.children), repmat({cfg}, size(categories)), repmat({coordinates}, size(categories)), 'UniformOutput', false);


end %end function


function [root, anchorPoints] = addNeighbourStructure(root)

elements = allElements(root);
anchorPoints = [];
for i = 1:length(elements)
    boundingBox = toBoundingBox(elements(i).anchorPoints(1, :), elements(i).anchorPoints(2, :));
    elements(i).boundingBox = boundingBox;
    anchorPoints = cat(1, anchorPoints, boundingBox);
    for j = 1:length(elements(i).cuboids)
        boundingBox = toBoundingBox(elements(i).cuboids(j).anchorPoints(1, :), elements(i).cuboids(j).anchorPoints(2, :));
        elements(i).cuboids(j).boundingBox = boundingBox;
        anchorPoints = cat(1, anchorPoints, boundingBox);
    end
end
anchorPoints = unique(anchorPoints, 'rows');
root = addAnchors(root, anchorPoints);
anchorPoints = [anchorPoints, ones(size(anchorPoints, 1), 1)];

end %end function


function root = addAnchors(root, anchorPoints)

[~, root.anchorIndices] = ismember(toBoundingBox(root.anchorPoints(1, :), root.anchorPoints(2, :)), anchorPoints, 'rows');
if ~isempty(root.cuboids)
    for i = 1:length(root.cuboids)
        [~, root.cuboids(i).anchorIndices] = ismember(toBoundingBox(root.cuboids(i).anchorPoints(1, :), root.cuboids(i).anchorPoints(2, :)), anchorPoints, 'rows');
    end
end
if ~isempty(root.children);    
    root.children = cellfun(@addAnchors, root.children, repmat({anchorPoints}, size(root.children)), 'UniformOutput', false);
end

end %end function


function boundingBox = toBoundingBox(lowerCorner, upperCorner)

boundingBox = [ ...
    lowerCorner(1), lowerCorner(2), lowerCorner(3); ... %1
    lowerCorner(1), lowerCorner(2), upperCorner(3); ... %2
    lowerCorner(1), upperCorner(2), lowerCorner(3); ... %3
    lowerCorner(1), upperCorner(2), upperCorner(3); ... %4
    upperCorner(1), lowerCorner(2), lowerCorner(3); ... %5
    upperCorner(1), lowerCorner(2), upperCorner(3); ... %6
    upperCorner(1), upperCorner(2), lowerCorner(3); ... %7
    upperCorner(1), upperCorner(2), upperCorner(3)];    %8

end %end function


function elements = allElements(root)

if isempty(root.children)
    elements = root;
    return;
else
    elements = cat(1, cellfun(@allElements, root.children, 'UniformOutput', false));
    elements = [root, elements{:}];
    return;
end
end %end function


function elements = elementsLevelN(root, N)
if N == 0
    elements = root;
    return;
elseif isempty(root.children)
    elements = [];
    return;
else
    elements = cat(1, cellfun(@elementsLevelN, root.children, repmat({N - 1}, size(root.children)), 'UniformOutput', false));
    elements = [elements{:}];
    return;
end
end %end function



