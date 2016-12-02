function [unresolved, assigned, called, ll, assinFn] = matlabParser(fname, MATLABorR, bIgnoreFnBody)
    if upper(MATLABorR(1)) == 'M'
        ao          = '='; % assignment operator
        delims      = {'{','(','[',']',')','}',',',  '-','+','*','/','\','==','>','<','^','!','@',':','&','|','&&','||', '~'};
        cmt         = '%';
        newCmd      = ';';
        structDelim = '.'; 
        strDelim    = {'''','"'};
        isR         = false;
    else
        ao          = '<\-';
        delims      = {'{','(','[',']',')','}',','  '-','+','*','/','\','==','>','<','^','!','@',':','&','|','&&','||','%*%','%>%','~','='};
        cmt         = '#';
        newCmd      = ';';
        structDelim = '$'; % list delim
        strDelim    = {'''','"'};
        isR         = true;
    end
    
    assigned    = utils.base.objStack;
    assinFn     = utils.base.objStack;
    called      = utils.base.objStack;
    unresolved  = utils.base.objStack;
    
    fndef       = 0;  % line is a function def
    fncounter   = 0;
    killNextLine= false;
    
    fileID      = fopen(fname);
    tline       = fgets(fileID);
    ll          = 0;
    
    if ~isR
        % MATLAB string parser in regex form. Not perfect, but pretty good.
        % (matches single quotes, understands '' as escaped '. Ignores transpose operator.)
        mxStrRE     = '(?:^|\n|[^a-zA-Z0-9_\)\}\]])+?(''[^'']*(?:(?:''{2})*[^'']*)++[^'']*+'')''?';
    else
        % modified R version (double quotes - don't need to worry about transposes or escapes!)
        % **** HOWEVER, ASSUMES USER HAS CODED ALWAYS WITH DOUBLE QUOTES IN
        % **** R. SINGLE QUOTES ARE PERMITTED BUT ARE < DOUBLE.
        mxStrRE     = '"[^"]*(?<!\\)"';
    end
    
    while ischar(tline)
        %speq = regexp(tline, '([^= ]+) *=(?!=) *(.*)', 'tokens');
        
        commentSoFar = false;  % comment so far on line...
        ll           = ll + 1;
        
%         if ll == 23
%             stophere = 1;
%         end
        
        % R stuff ---------------------------------------------------------
        % This is mega hack-y. Not recommended.
        if isR
            if fncounter > 0
                [pos, fncounter] = findMatchingCharacter(tline, '{', '}', fncounter);
                if pos > 0
                    fndef = 0;
                    tline = tline(pos+1:end);
                end 
            end
            % margrittr pipe problems: after %>%, operations can be
            % specified working in namespace of df. (like a WITH).
            % While this is hacky, it is the easiest way to deal with this.
            
            tlsplit     = strsplit(tline, '%>%');
            delimspl    = strsplit(tline, delims);
            killCurLine = killNextLine;
            
            if ~killCurLine
                tline   = tlsplit{1};
            else
                % if killing next line
                tline   = '';
                if regexp(delimspl{end}, '\n') % ie line not yet ended
                    % do nothing
                else
                    % stop eating up next line
                    killNextLine = false;
                end
            end
            
            if numel(tlsplit) > 1 && isempty(strtrim(tlsplit{end})) % continue onto next line
                killNextLine = true;
            end
        end
        % -----------------------------------------------------------------
        
        % deal with function body
        fndef        = min(fndef, 1);  % no longer fn defn line if previous
        
        % note for MATLAB, only the first function will be returned.
        if fndef && bIgnoreFnBody
            tline       = fgets(fileID);
            continue
        end
        
        % ignore comments
        tline = strtrim(tline);
        if isempty(tline) || tline(1) == cmt
            tline       = fgets(fileID);
            continue
        end
        
        % remove strings
        % see explanation sheet for the regex here...!
        tline = utils.txt.regexprep2(tline, mxStrRE, '');
        
        % split line into command-based tokens (were there multiple
        splitCmd = strsplit(tline, newCmd);
        for cmd = splitCmd
            splitEq  = strsplit(cmd{1},['(?<=[^=<>])',ao,'(?=[^=])'],'DelimiterType','RegularExpression');
            numSEq   = numel(splitEq);
            for elnum = 1:numSEq
                el       = splitEq{elnum};
                splitStr = strsplit(el, delims, 'CollapseDelimiters', true);
                
                for strnum = 1:numel(splitStr)
                    
                    str  = splitStr{strnum};
                    str  = strrep(str,'=',''); % remove = from <=, >=, += etc)
                    str  = strtrim(str);   % remove trailing/leading wspace
                    
                    % ignore some special cases
                    if isempty(str)
                        continue
                    end
                    hasString = false;
                    for kk = 1:numel(strDelim)
                        if strfind(str, strDelim{kk})
                            % string involved somewhere
                            hasString = true;
                        end
                    end
                    if hasString
                        continue
                    end
                    
                    % no quotes/strings anymore. Now remove spaces
                    nows = strsplit(str, '\s', 'DelimiterType', 'RegularExpression');
                    
                    for wsnum = 1:numel(nows)
                        finstr = nows{wsnum};
                        
                        % trivial cases
                        if isempty(finstr)
                            continue
                        elseif strcmp(finstr(1), cmt)
                            % comment --> ignore
                            commentSoFar = true;
                            continue
                        end
                        
                        % function stuff
                        if strcmp(finstr, 'function')
                            fndef = 3;  % 3 = pre function def
                            if isR
                                fncounter = 1;
                            end
                            continue
                        end
                        
                        % only take first string after = for fndef
                        if fndef == 3 && elnum == 2 && strnum > 1
                            fndef = 2;
                        end
                        
                        % remove struct stuff
                        while strfind(finstr, structDelim)
                            finstr = regexprep(finstr, ['(\',structDelim, '.*$)'], '');
                        end

                        % is numeric (decimal removed above)
                        if all(isstrprop(finstr, 'digit')) || all(isstrprop(finstr, 'wspace'))
                            % numeric / whitespace --> ignore
                            continue
                        end
                        
                        % save if not commented yet on line
                        if ~commentSoFar
                            if (fndef < 2 && elnum == 1 && numSEq > 1 ) ...     % elements before assignment
                                    || (fndef == 2 && elnum == 2) ...           % fn: after function name
                                    || (fndef == 3 && elnum == 2 && wsnum == 1) % fn: function name
                                
                                assigned.uniquePush(finstr);
                                if fndef
                                    assinFn.push(finstr);
                                end
                               
                            elseif fndef < 2
                                called.uniquePush(finstr);
                                if ~assigned.ismember(finstr)
                                    unresolved.uniquePush(finstr);
                                end
                            end
                        end
                    end
                end
            end
        end
        tline       = fgets(fileID);
    end
    
    fclose(fileID);
    
    % check if unresolved references are system files
    tmp = unresolved.contents;
    unresolved = utils.base.objStack;
    for ii = 1:numel(tmp)
        if isempty(which(tmp{ii}))
            unresolved.push(tmp{ii});
        end
    end
    unresolved = unresolved.contents;
    assigned   = assigned.contents;
%     assigned(strcmp(assigned, 'function')) = [];
    called     = called.contents;
    assinFn    = unique(assinFn.contents);
    if nargout > 4
        assigned = setdiff(assigned, assinFn);
    end
end


function [pos, counter] = findMatchingCharacter(inpLine, charOpen, charClose, counter)
    pos = 0;
    for cc = 1:numel(inpLine)
        c  = inpLine(cc);
        if c == charOpen
            counter = counter + 1;
        elseif c == charClose
            counter = counter -1;
        end
        if counter == 0
            pos = c;
            return
        end
    end
end

