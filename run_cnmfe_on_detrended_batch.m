function summary = run_cnmfe_on_detrended_batch(det_root)
% RUN_CNMFE_ON_DETRENDED_BATCH  Run CNMF-E on all *_det.mat files in a folder tree.
%
%   SUMMARY = RUN_CNMFE_ON_DETRENDED_BATCH(DET_ROOT) searches recursively for
%   files ending with "_det.mat" beneath DET_ROOT, runs CNMF-E on each file,
%   and saves the extracted spatial (A) and temporal (C, C_raw) components to
%   "*_cnmfe.mat" files next to the inputs. The returned SUMMARY structure
%   records the status and output path for every processed dataset.
%
%   Example:
%       summary = run_cnmfe_on_detrended_batch('D:/Data/my_mouse');
%
%   See also RUN_CNMFE_SESSION, CLEANUP_CNMFE_ARTIFACTS.

arguments
    det_root (1,1) string
end

det_root = char(det_root);
if ~isfolder(det_root)
    error('The provided folder "%s" does not exist.', det_root);
end

i_add_required_paths();

det_listing = dir(fullfile(det_root, '**', '*_det.mat'));
det_listing = det_listing(~[det_listing.isdir]);
if isempty(det_listing)
    error('No files ending with "_det.mat" were found under "%s".', det_root);
end

summary = repmat(struct('input_file', '', 'output_file', '', 'roi_count', 0, ...
    'status', '', 'message', ''), numel(det_listing), 1);

fprintf('Found %d detrended dataset(s) to process.\n', numel(det_listing));

for idx = 1:numel(det_listing)
    file_path = fullfile(det_listing(idx).folder, det_listing(idx).name);
    summary(idx).input_file = file_path;
    fprintf('\n[%d/%d] %s\n', idx, numel(det_listing), file_path);

    artifacts = [];
    try
        cali_options = struct();
        try
            cali_options = CaliAli_load(file_path, 'CaliAli_options');
        catch
            fprintf('  Warning: CaliAli_options not found in file. Using defaults.\n');
        end

        [neuron, artifacts] = run_cnmfe_session(file_path, cali_options);

        A = neuron.A;
        C = neuron.C;
        C_raw = neuron.C_raw;
        if isempty(C)
            C = C_raw;
        end

        [~, name] = fileparts(file_path);
        output_file = fullfile(det_listing(idx).folder, [name '_cnmfe.mat']);
        save(output_file, 'A', 'C', 'C_raw', '-v7.3');

        summary(idx).output_file = output_file;
        summary(idx).roi_count = size(A, 2);
        summary(idx).status = 'success';
        fprintf('  CNMF-E detected %d ROI(s). Results saved to %s\n', ...
            summary(idx).roi_count, output_file);

        cleanup_cnmfe_artifacts(artifacts);
        clear neuron;
    catch ME
        summary(idx).status = 'error';
        summary(idx).message = ME.message;
        fprintf('  Error processing file: %s\n', ME.message);
        cleanup_cnmfe_artifacts(artifacts);
    end
end

end

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
