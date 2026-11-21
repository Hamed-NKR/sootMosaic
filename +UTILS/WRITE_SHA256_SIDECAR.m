function [hash_text, sidecar] = WRITE_SHA256_SIDECAR(file_path)
% "WRITE_SHA256_SIDECAR" writes the digest beside a data product.
% ----------------------------------------------------------------------- %
%
% Inputs:
%     file_path: File to hash
% ----------------------------------------------------------------------- %
%
% Outputs:
%     hash_text: Lowercase SHA-256 digest for the producer run record
%     sidecar: Companion path with the .sha256 suffix. The line contains...
%         ...the digest, two spaces, the file name and a line feed
% ----------------------------------------------------------------------- %

hash_text = UTILS.FILE_SHA256(file_path);
sidecar = [char(file_path) '.sha256'];
fid = fopen(sidecar, 'wb');
if fid < 0
    error('sootMosaic:WRITE_SHA256_SIDECAR:SidecarWriteFailed', ...
        'Could not open the checksum sidecar.');
end
cleanup = onCleanup(@() fclose(fid));
[~, name, ext] = fileparts(file_path);
line = sprintf('%s  %s%s\n', hash_text, name, ext);
count = fwrite(fid, line, 'char');
if count ~= numel(line)
    error('sootMosaic:WRITE_SHA256_SIDECAR:SidecarWriteFailed', ...
        'Could not write the complete checksum sidecar.');
end
end
