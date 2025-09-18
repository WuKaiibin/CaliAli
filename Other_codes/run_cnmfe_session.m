function [neuron, artifacts] = run_cnmfe_session(input_path, CaliAliOptions)
% RUN_CNMFE_SESSION  Execute CNMF-E on a single data file.
%
%   [NEURON, ARTIFACTS] = RUN_CNMFE_SESSION(INPUT_PATH) runs CNMF-E using the
%   default CaliAli parameter set on the dataset specified by INPUT_PATH,
%   which can be a .mat, .tif, or other supported imaging file. The returned
%   NEURON object contains the extracted spatial and temporal components, and
%   ARTIFACTS lists temporary folders/files created by CNMF-E so callers can
%   remove them if desired.
%
%   [...] = RUN_CNMFE_SESSION(INPUT_PATH, CALIALIOPTIONS) uses the provided
%   CaliAli options structure to configure CNMF-E. Only the fields required
%   by CNMF-E are accessed; missing fields are automatically populated with
%   defaults from CNMFE_PARAMETERS.
%
%   See also: RUNCNMFE, CNMFE_PARAMETERS, CLEANUP_CNMFE_ARTIFACTS.

arguments
    input_path (1,1) string
    CaliAliOptions struct = struct()
end

input_path = char(input_path);
if ~isfile(input_path)
    error('The provided input file "%s" does not exist.', input_path);
end

if ~isfield(CaliAliOptions, 'cnmf') || isempty(CaliAliOptions.cnmf)
    pars = CNMFE_parameters();
    CaliAliOptions.cnmf = pars;
else
    pars = CaliAliOptions.cnmf;
end

if ~isfield(CaliAliOptions, 'preprocessing') || ...
        ~isfield(CaliAliOptions.preprocessing, 'structure') || ...
        isempty(CaliAliOptions.preprocessing.structure)
    CaliAliOptions.preprocessing = struct('structure', 'neuron');
end

if ~isfield(CaliAliOptions.cnmf, 'merge_thr_spatial') || ...
        isempty(CaliAliOptions.cnmf.merge_thr_spatial)
    CaliAliOptions.cnmf.merge_thr_spatial = pars.merge_thr_spatial;
end

neuron = Sources2D();
neuron = fill_neuron(neuron, pars);
neuron.options = fill_neuron(neuron.options, pars);
neuron.CaliAli_options = CaliAliOptions;
neuron.show_merge = 0;

neuron.select_data(input_path);
neuron.getReady();

cleanup_folders = {};
cleanup_files = {};

if isfield(neuron.P, 'folder_analysis') && ~isempty(neuron.P.folder_analysis)
    cleanup_folders{end+1} = neuron.P.folder_analysis; %#ok<AGROW>
end

[neuron, ~] = initComponents_parallel_PV(neuron, [], [], 0, true, false);

if isfield(neuron.P, 'log_folder') && ~isempty(neuron.P.log_folder)
    cleanup_folders{end+1} = neuron.P.log_folder; %#ok<AGROW>
end
if isfield(neuron.P, 'log_data') && ~isempty(neuron.P.log_data)
    cleanup_files{end+1} = neuron.P.log_data; %#ok<AGROW>
end

A_prev = neuron.A;
C_prev = neuron.C_raw;
max_iterations = 10;
for loop_idx = 1:max_iterations
    neuron = CNMF_CaliAli_update('Background', neuron);
    neuron = CNMF_CaliAli_update('Spatial', neuron);
    neuron = CNMF_CaliAli_update('Temporal', neuron);
    neuron.remove_false_positives();
    neuron.merge_neurons_dist_corr(neuron.show_merge);
    neuron.merge_high_corr(neuron.show_merge, neuron.CaliAli_options.cnmf.merge_thr_spatial);
    neuron.merge_high_corr(neuron.show_merge, [0.9, -inf, -inf]);
    dissimilarity = dissimilarity_previous(A_prev, neuron.A, C_prev, neuron.C_raw);
    fprintf('    CNMF-E iteration %d, dissimilarity = %.3f\n', loop_idx, dissimilarity);
    if dissimilarity < 0.05
        break;
    end
    A_prev = neuron.A;
    C_prev = neuron.C_raw;
end

neuron = update_residual_Cn_PNR_batch(neuron);
scale_to_noise(neuron);
neuron.C_raw = detrend_Ca_traces(neuron.sf * 2, neuron.C_raw, get_batch_size(neuron));
neuron = postprocessDeconvolvedTraces(neuron, 'foopsi', 'ar2', -5);
neuron.orderROIs('snr');

artifacts = struct('folders', {cleanup_folders}, 'files', {cleanup_files});
end
