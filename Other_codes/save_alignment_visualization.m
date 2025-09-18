function save_alignment_visualization(P, sessionLabels, stageLabels, outputPath)
% SAVE_ALIGNMENT_VISUALIZATION  Save overview figure of alignment stages.
%
%   SAVE_ALIGNMENT_VISUALIZATION(P, SESSIONLABELS, STAGELABELS, OUTPUTPATH)
%   receives the table of projections returned by CALIALI_ALIGN_SESSIONS and
%   generates a PNG summary showing, for each session and processing stage,
%   the fused blood vessel / neuron projections used during alignment.
%
%   SESSIONLABELS is a cell array with one label per session. When empty, the
%   labels default to "Session #". STAGELABELS should contain the names of the
%   alignment stages (e.g. {'Original','Translations','CaliAli'}). If omitted
%   the table variable names are used. OUTPUTPATH specifies the destination
%   image file.

if nargin < 4 || isempty(outputPath)
    error('An output path must be provided for the visualization.');
end

if nargin < 3 || isempty(stageLabels)
    stageLabels = P.Properties.VariableNames;
else
    stageLabels = cellstr(stageLabels);
end

stages = numel(stageLabels);

% Extract fused projections for the first stage to determine session count.
firstStage = i_extract_fused_stack(P, stageLabels{1});
numSessions = size(firstStage, 4);

if nargin < 2 || isempty(sessionLabels)
    sessionLabels = arrayfun(@(k) sprintf('Session %d', k), 1:numSessions, 'UniformOutput', false);
else
    sessionLabels = cellstr(sessionLabels);
    if numel(sessionLabels) ~= numSessions
        warning('Number of session labels does not match the number of sessions. Using generic labels.');
        sessionLabels = arrayfun(@(k) sprintf('Session %d', k), 1:numSessions, 'UniformOutput', false);
    end
end

fig = figure('Visible', 'off', 'Color', 'w');
t = tiledlayout(fig, stages, numSessions, 'Padding', 'compact', 'TileSpacing', 'compact'); %#ok<NASGU>

for s = 1:stages
    fusedStack = i_extract_fused_stack(P, stageLabels{s});
    for sess = 1:numSessions
        ax = nexttile; %#ok<LNEXT>
        img = squeeze(fusedStack(:, :, :, sess));
        imshow(img, 'Parent', ax);
        axis(ax, 'image');
        ax.Visible = 'off';
        if s == 1
            title(ax, sessionLabels{sess}, 'Interpreter', 'none');
        end
        if sess == 1
            ylabel(ax, stageLabels{s}, 'Interpreter', 'none', 'FontWeight', 'bold');
        end
    end
end

exportgraphics(fig, outputPath, 'Resolution', 200);
close(fig);

end

% -------------------------------------------------------------------------
function fusedStack = i_extract_fused_stack(P, stageLabel)

if ischar(stageLabel) || isstring(stageLabel)
    stageData = P.(char(stageLabel));
else
    stageData = P.(stageLabel);
end

try
    fusedStack = stageData(1, :).(5){1, 1};
catch
    error('Unable to extract fused projections for stage "%s".', stageLabel);
end

if ndims(fusedStack) == 3
    % Ensure the 4th dimension encodes the session index.
    fusedStack = reshape(fusedStack, size(fusedStack, 1), size(fusedStack, 2), size(fusedStack, 3), 1);
end

end

