function cleanup_cnmfe_artifacts(artifacts)
% CLEANUP_CNMFE_ARTIFACTS  Remove temporary files and folders created by CNMF-E.
%
%   CLEANUP_CNMFE_ARTIFACTS(ARTIFACTS) deletes the files and directories
%   listed in the structure returned by RUN_CNMFE_SESSION. Missing entries
%   are ignored silently so the function is safe to call even if processing
%   failed midway.

if nargin == 0 || isempty(artifacts)
    return;
end

if isfield(artifacts, 'files')
    file_list = artifacts.files;
    for i = 1:numel(file_list)
        i_safe_delete(file_list{i});
    end
end

if isfield(artifacts, 'folders')
    folder_list = artifacts.folders;
    for i = 1:numel(folder_list)
        i_safe_rmdir(folder_list{i});
    end
end

end

function i_safe_delete(file_path)
if ~isempty(file_path) && exist(file_path, 'file')
    try
        delete(file_path);
    catch
    end
end
end

function i_safe_rmdir(folder_path)
if ~isempty(folder_path) && isfolder(folder_path)
    try
        rmdir(folder_path, 's');
    catch
    end
end
end
