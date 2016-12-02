% Example use of matlabParser. This attempts to resolve all references that are unresolved in
% each file by cross referencing amongst all files parsed.
% Dependency graphs are output that can be read by Gephi for visualisation.
%
% File depends on utils package again, but not for anything important.

dirs = cell(2,1);
dirs{1} = './original/scripts';
dirs{2} = './original/src';


file_features = cell(5,0);
pb = utils.base.objProgressBar;

for jj = 1:numel(dirs)
    cDir = dirs{jj};
    cFiles = dir(cDir);
    nFiles = numel(cFiles);
    pb.newProgressBar('file: ', 30, true, true);
    
    for ii = 1:nFiles
        if ~cFiles(ii).isdir && cFiles(ii).name(end) == 'm'
            pb.updateText(sprintf('file: %s ', cFiles(ii).name));
            pb.print(ii/nFiles);
            [unresolved, assigned, called, lc, assinFn] = ...
                matlabParser([cDir,'/', cFiles(ii).name], 'M', false);
            file_features = [file_features, {cFiles(ii).name; lc; assigned; called; unresolved}];
        end
    end
    pb.finish;
end


%% Add nodes where dependencies not found
nFiles         = size(file_features, 2);
filedeps       = [file_features; cell(2, nFiles)];
depok          = {'on','off','for', 'optim', 'SwitchToMedScale'}; %(internal optim options)
depok          = [depok, {'sed'}];
% file features is: (name, linecount, assign, call, unresolved, dependencies, orphans)

% find all dependencies between files
for jj = 1:nFiles
    dep      = false(nFiles,1);
    orphan   = {};
    for ii = 1:numel(file_features{5,jj})
        curDep = file_features{5,jj}{ii};
        
        % process dep for number or lambda function
        if ~isempty(regexp(curDep, '^[0-9.]+e[0-9.]*$', 'once')) ...
            || ~isempty(regexp(curDep, '^[0-9. ]*$', 'once'))
            continue
        end
        if curDep(1) == '@'
            curDep = curDep(2:end);
        end
        
        % find dependency
        if ~ismember(curDep, depok)
            found = false;
            for kk = 1:nFiles
                % if dependency is of file name, we're done
                if strcmp(curDep, file_features{1,kk}(1:end-2))
                    dep(kk) = 1;
                    found = true;
                    break
                end
                % is dependency assigned in another file?
                if ismember(curDep, file_features{3,kk})
                    dep(kk) = 1;
                    found = true;
                    % > do not break, since multiple files may provide dep
                end
            end
            
            if ~found
                orphan = [orphan, curDep];
            end
        end
    end
    
    filedeps{6,jj} = find(dep);
    filedeps{7,jj} = orphan;
end
%%
% Add orphans
allorphans = {};
for jj = 1:nFiles
    allorphans = union(allorphans, filedeps{7,jj});
end
nOrphans = numel(allorphans);
nTotal   = nFiles + nOrphans;

filedeps = [filedeps, cell(7, nOrphans)];
for oo = 1:nOrphans
    orphName              = allorphans{oo};
    filedeps{1,nFiles+oo} = orphName;
    for jj = 1:nFiles
        if ismember(orphName, filedeps{7, jj})
            filedeps{7, jj} = setdiff(filedeps{7, jj}, orphName);
            filedeps{6, jj} = union(nFiles+oo, filedeps{6,jj});
        end
    end
end

%% Get dependency graph
graphdep = false(nTotal, nTotal);
for jj = 1:nFiles
    graphdep(jj, filedeps{6,jj}) = true;
end
graphdep = graphdep';    % for gephi

% files with no dependencies
nodeps = false(nTotal,1);
for jj = 1:nTotal
    if all(~graphdep(jj,:)) && all(~graphdep(:,jj))
        nodeps(jj) = true;
    end
end
    
% attributes: (name, line count, is found)
nodeAttributes = cell(3,nTotal);
nodeAttributes(1:2,:) = filedeps(1:2,:);
for jj = 1:nTotal
    if jj > nFiles
        nodeAttributes{2,jj} = 3;  % to stop node shrinking to 0
        nodeAttributes{3,jj} = 0;
    else
        nodeAttributes{3,jj} = 1;
    end
end


%% Get similarity graph
graphsim            = NaN(nTotal, nTotal);
graphsim(1:nTotal+1:nTotal*nTotal) = 1;   % set diagonal to 1

for jj = 1:nFiles
    for kk = 1:nFiles
        if kk <= jj
            graphsim(jj,kk) = graphsim(kk,jj);
        else
            distAss         = utils.math.jaccard(filedeps{3,jj}, filedeps{3,kk});
            distCall        = utils.math.jaccard(filedeps{4,jj}, filedeps{4,kk});
            graphsim(jj,kk) = 0.5*distAss + 0.5*distCall;
        end
    end
end


% Remove all files with no dependency
graphsim       = graphsim(~nodeps,~nodeps);
graphdep       = graphdep(~nodeps,~nodeps);
nodeAttributes = nodeAttributes(:,~nodeps);
nTotal         = sum(~nodeps);
graphmix       = graphsim + 0.5*(graphdep+graphdep');
%% Process for output

nodeAttributes = [num2cell(1:nTotal); nodeAttributes];
utils.struct.writeCell(nodeAttributes', '%d,%s,%d,%d\n', 'codeNodes.csv');
%%
edges = zeros(nTotal*nTotal, 5);
for jj = 1:nTotal
    for kk = 1:nTotal
        edges((jj-1)*nTotal + kk,:) = [jj, kk, graphmix(jj,kk), graphsim(jj,kk), graphdep(jj,kk)];
    end
end
edges(isnan(edges)) = 0;

edgesC = num2cell(edges);
edgesC = [edgesC(:,1:2), repmat({'Directed'},nTotal*nTotal,1), edgesC(:,3:end)];
utils.struct.writeCell(edgesC, '%d,%d,%s,%.5f,%.5f,%d\n', 'codeEdges.csv');


%% Prune
node = 3;
nodeName = 'testfname.m';
node     = find(strcmp(nodeName, filedeps(1,:)));
assert(~isempty(node), '%s -- not found! Ensure file extension is correct.', nodeName);

fprintf('%s ====================\n', filedeps{1,node});
tmp = cell(numel(filedeps{5,node}),1);
ignore = false(numel(filedeps{5,node}),1);
for kk = 1:numel(filedeps{5,node})
    tmp{kk} = {};
    curDep = filedeps{5,node}{kk};
    
    if ~isempty(regexp(curDep, '^[0-9.]+e[0-9.]*$', 'once')) ...
            || ~isempty(regexp(curDep, '^[0-9. ]*$', 'once')) ...
            || ismember(curDep, depok)
        ignore(kk) = true;
        continue
    end
        
    
    for jj = 1:nFiles
        if ~isempty(filedeps{3,jj}) 
            if ismember(curDep, filedeps{3,jj})
                tmp{kk} = [tmp{kk}, filedeps{1,jj}];
            end
        end
    end

end

% always align_ceff_vitals and data_load_prepr (3,7)
always = [3,7];
tick   = false(2,1);
for kk = 1:numel(filedeps{5,node})
    if ~isempty(tmp{kk})
        if ismember(filedeps{1,always(1)}, tmp{kk})
            tmp{kk}    = {};
            tick(1)    = true;
            ignore(kk) = true;
        elseif ismember(filedeps{1,always(2)}, tmp{kk})
            tmp{kk}    = {};
            tick(2)    = true;
            ignore(kk) = true;
        end
    end
end

for kk = 1:numel(filedeps{5,node})
    if ~ismember(kk,find(ignore))
        fprintf('--- %s ---\n', filedeps{5,node}{kk});
        for jj = 1:numel(tmp{kk})
            fprintf('%s\n', tmp{kk}{jj});
        end
    end
end
for jj = 1:2
    if tick(jj); fprintf('--- %s ---\n', filedeps{1,always(jj)}); end
end

