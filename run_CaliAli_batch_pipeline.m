function summary = run_CaliAli_batch_pipeline(data_root)
% RUN_CALIALI_BATCH_PIPELINE  Process multi-day one-photon imaging datasets.
%
%   SUMMARY = RUN_CALIALI_BATCH_PIPELINE(DATA_ROOT) reads all AVI videos
%   stored beneath DATA_ROOT, performs motion correction, aligns each day to
%   the first day, runs CNMF-E on the aligned data for every day, and saves a
%   ROI overlay figure for visual inspection of the cross-day alignment. The
%   pipeline requires only the root folder path; no manual file selection or
%   configuration is needed. Intermediate .mat files are not written to disk;
%   temporary files created for CNMF-E are stored inside a unique temporary
%   folder that is deleted automatically once processing completes.
%
%   The returned SUMMARY structure contains the configuration, processing
%   status, and CNMF-E outputs (including the spatial footprints A) for each
%   processed day. ROI visualisations are saved as PNG files in a
%   "cnmfe_roi_visualizations" folder inside DATA_ROOT.
%
%   Example:
%       summary = run_CaliAli_batch_pipeline('D:/MyDataset');
%
%   See also NORMCORRE_BATCH, CNMFE_PARAMETERS.

arguments
    data_root (1,1) string
end

data_root = char(data_root);
if ~isfolder(data_root)
    error('The provided data_root "%s" does not exist.', data_root);
end

% Add all toolboxes required by the pipeline.
i_add_required_paths();

% Discover days that contain AVI files.
day_entries = i_find_day_folders(data_root);
if isempty(day_entries)
    error('No AVI files were found under "%s".', data_root);
end

output_dir = fullfile(data_root, 'cnmfe_roi_visualizations');
if ~isfolder(output_dir)
    mkdir(output_dir);
end

fprintf('Found %d day(s) to process.\n', numel(day_entries));

summary = struct();
summary.data_root = data_root;
summary.reference_day = '';
summary.days = struct('index', {}, 'name', {}, 'path', {}, 'sessions', {}, ...
    'alignment', {}, 'cnmfe', {}, 'mean_frame', {});

reference_image = [];
reference_name = '';

for day_idx = 1:numel(day_entries)
    day_info = day_entries(day_idx);
    fprintf('\n[%d/%d] Day "%s"\n', day_idx, numel(day_entries), day_info.name);

    session_files = i_collect_avi_files(day_info.path);
    if isempty(session_files)
        fprintf('  No AVI sessions found inside "%s". Skipping.\n', day_info.path);
        continue;
    end

    % Motion correct each session.
    [sessions_data, session_summary] = i_motion_correct_sessions(session_files);

    % Concatenate sessions along the temporal dimension.
    concatenated = cat(3, sessions_data{:});

    mean_frame = mean(concatenated, 3);

    if isempty(reference_image)
        aligned_video = concatenated;
        aligned_mean = mean_frame;
        transform = struct('type', 'identity', 'translation', [0, 0], ...
            'matrix', eye(3));
        reference_image = aligned_mean;
        reference_name = day_info.name;
    else
        [aligned_video, aligned_mean, transform] = i_align_to_reference(concatenated, reference_image);
    end
    clear concatenated;

    % Run CNMF-E on the aligned video and produce ROI visualisation.
    cnmfe_info = i_run_cnmfe_for_day(aligned_video, aligned_mean, day_info.name, day_idx, output_dir);
    clear aligned_video;

    day_struct = struct();
    day_struct.index = day_idx;
    day_struct.name = day_info.name;
    day_struct.path = day_info.path;
    day_struct.sessions = session_summary;
    day_struct.alignment = transform;
    day_struct.cnmfe = cnmfe_info;
    day_struct.mean_frame = aligned_mean;

    summary.days(end+1,1) = day_struct; %#ok<AGROW>
end

summary.reference_day = reference_name;

fprintf('\nProcessing complete. ROI figures are saved in %s\n', output_dir);

end

% -------------------------------------------------------------------------
function i_add_required_paths()
root_dir = fileparts(mfilename('fullpath'));
subdirs = {
    'Downsample', ...
    'Motion_Correction/NoRMCorre-master', ...
    'Motion_Correction/other codes', ...
    'CNMF-e', ...
    'CNMF-e/ca_source_extraction', ...
    'CNMF-e/CaliAli_modified_codes', ...
    'CNMF-e/OASIS_matlab', ...
    'Other_codes', ...
    'Other_codes/Experimental', ...
    'Postprocessing'
    };
for i = 1:numel(subdirs)
    dir_path = fullfile(root_dir, subdirs{i});
    if isfolder(dir_path)
        addpath(genpath(dir_path));
    end
end
end

% -------------------------------------------------------------------------
function day_entries = i_find_day_folders(root_dir)
entries = dir(root_dir);
entries = entries([entries.isdir]);
entries = entries(~ismember({entries.name}, {'.', '..'}));

day_entries = struct('name', {}, 'path', {});
for i = 1:numel(entries)
    candidate_path = fullfile(root_dir, entries(i).name);
    if ~isempty(i_collect_avi_files(candidate_path))
        day_entries(end+1,1) = struct('name', entries(i).name, ...
            'path', candidate_path); %#ok<AGROW>
    end
end

if isempty(day_entries)
    avi_files = i_collect_avi_files(root_dir);
    if ~isempty(avi_files)
        [~, folder_name] = fileparts(root_dir);
        day_entries = struct('name', folder_name, 'path', root_dir);
    end
end

% Sort by name for deterministic processing order.
if ~isempty(day_entries)
    [~, order] = sort(lower({day_entries.name}));
    day_entries = day_entries(order);
end
end

% -------------------------------------------------------------------------
function files = i_collect_avi_files(folder)
listing = dir(folder);
listing = listing(~[listing.isdir]);
if isempty(listing)
    files = {};
    return;
end
names = {listing.name};
mask = endsWith(lower(names), '.avi');
files = fullfile(folder, names(mask));
if isempty(files)
    files = {};
    return;
end
[~, order] = sort(lower(names(mask)));
files = files(order);
end

% -------------------------------------------------------------------------
function [videos, summaries] = i_motion_correct_sessions(session_files)
num_sessions = numel(session_files);
videos = cell(num_sessions, 1);
summaries = repmat(struct('file', '', 'frames', 0, 'height', 0, 'width', 0), num_sessions, 1);

for idx = 1:num_sessions
    file_path = session_files{idx};
    fprintf('  Motion correcting session %d/%d: %s\n', idx, num_sessions, file_path);
    raw = single(load_avi(file_path));
    if ~isempty(raw)
        raw = raw - min(raw(:));
        max_val = max(raw(:));
        if max_val > 0
            raw = raw ./ max_val;
        end
    end
    corrected = i_motion_correct_video(raw);
    videos{idx} = corrected;
    summaries(idx).file = file_path;
    summaries(idx).frames = size(corrected, 3);
    summaries(idx).height = size(corrected, 1);
    summaries(idx).width = size(corrected, 2);
    clear raw corrected;
end
end

% -------------------------------------------------------------------------
function corrected = i_motion_correct_video(video)
if isempty(video)
    corrected = video;
    return;
end
options = NoRMCorreSetParms('d1', size(video, 1), 'd2', size(video, 2), ...
    'bin_width', min(200, size(video, 3)), 'max_shift', 20, 'iter', 1, ...
    'correct_bidir', false, 'shifts_method', 'fft');
corrected = normcorre_batch(video, options);
corrected = single(corrected);
end

% -------------------------------------------------------------------------
function [aligned_video, aligned_mean, transform] = i_align_to_reference(video, reference)
moving_mean = mean(video, 3);
reference = single(reference);
moving_mean = single(moving_mean);

try
    tform = imregcorr(moving_mean, reference, 'translation');
catch
    warning('imregcorr failed; falling back to identity transform.');
    tform = affine2d(eye(3));
end

r_fixed = imref2d(size(reference));
aligned_video = zeros([size(reference), size(video, 3)], 'like', video);
for k = 1:size(video, 3)
    aligned_video(:, :, k) = imwarp(video(:, :, k), tform, ...
        'OutputView', r_fixed, 'FillValues', 0);
end
aligned_mean = mean(aligned_video, 3);
transform = struct('type', 'translation', 'translation', tform.T(3, 1:2), ...
    'matrix', tform.T);
end

% -------------------------------------------------------------------------
function cnmfe_info = i_run_cnmfe_for_day(video, mean_image, day_name, day_idx, output_dir)
work_dir = tempname;
mkdir(work_dir);
cleanup_obj = onCleanup(@() i_safe_rmdir(work_dir));

tiff_path = fullfile(work_dir, 'aligned_video.tif');
i_write_tiff_stack(video, tiff_path);

[neuron, artifacts] = run_cnmfe_session(tiff_path);

A = neuron.A;
roi_figure = i_save_roi_overlay(A, mean_image, day_name, day_idx, output_dir);

cnmfe_info = struct();
cnmfe_info.A = A;
cnmfe_info.roi_count = size(A, 2);
cnmfe_info.roi_figure = roi_figure;
if isprop(neuron, 'Cn') && ~isempty(neuron.Cn)
    cnmfe_info.Cn = neuron.Cn;
else
    cnmfe_info.Cn = [];
end

clear neuron;

cleanup_cnmfe_artifacts(artifacts);
fprintf('  CNMF-E detected %d ROI(s).\n', cnmfe_info.roi_count);
fprintf('  ROI figure saved to %s\n', roi_figure);
end

% -------------------------------------------------------------------------
function i_write_tiff_stack(video, path)
video(isnan(video)) = 0;
scaled = i_scale_to_uint16(video);
opts = struct('compress', 'no', 'overwrite', true, 'big', true);
saveastiff(scaled, path, opts);
end

% -------------------------------------------------------------------------
function data_uint16 = i_scale_to_uint16(video)
video = single(video);
min_val = min(video(:));
video = video - min_val;
max_val = max(video(:));
if max_val > 0
    video = video ./ max_val;
end
data_uint16 = uint16(video * 65535);
end

% -------------------------------------------------------------------------
function i_safe_rmdir(folder_path)
if ~isempty(folder_path) && isfolder(folder_path)
    try
        rmdir(folder_path, 's');
    catch
    end
end
end

% -------------------------------------------------------------------------
function figure_path = i_save_roi_overlay(A, background, day_name, day_idx, output_dir)
if ~isfolder(output_dir)
    mkdir(output_dir);
end

background = double(background);
num_rois = size(A, 2);

A_full = full(A);
if isempty(A_full)
    A_full = zeros(numel(background), 0);
end
A_full = reshape(A_full, size(background, 1), size(background, 2), []);

fig = figure('Visible', 'off');
imagesc(background);
colormap gray;
axis image off;
hold on;

for roi_idx = 1:num_rois
    component = A_full(:, :, roi_idx);
    if ~any(component(:))
        continue;
    end
    component = component ./ max(component(:));
    bw = component > 0.3;
    if ~any(bw(:))
        [~, max_idx] = max(component(:));
        [r, c] = ind2sub(size(component), max_idx);
        plot(c, r, 'r.');
        continue;
    end
    boundaries = bwboundaries(bw);
    if isempty(boundaries)
        continue;
    end
    lengths = cellfun(@(b) size(b, 1), boundaries);
    [~, max_length_idx] = max(lengths);
    contour_coords = boundaries{max_length_idx};
    plot(contour_coords(:, 2), contour_coords(:, 1), 'r', 'LineWidth', 0.8);
end

title(sprintf('%s - CNMF-E ROIs (n = %d)', day_name, num_rois), 'Interpreter', 'none');

figure_path = fullfile(output_dir, sprintf('%02d_%s_rois.png', day_idx, i_safe_filename(day_name)));
saveas(fig, figure_path);
close(fig);
end

% -------------------------------------------------------------------------
function safe_name = i_safe_filename(name)
safe_name = regexprep(name, '[^a-zA-Z0-9_-]', '_');
if isempty(safe_name)
    safe_name = 'day';
end
end
