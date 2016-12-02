# matlabParser
A file to parse called and assigned variables in MATLAB

This function is a regex-based parser which (in most cases!) will record all variable names that are assigned in a script, and all variable names that are called. If a variable is called without being assigned, it will be returned as an unresolved variable. The function is motivated by a project in which I obtained around 60 files, many of which were scripts loading variables into the workspace, for which I had no sensible documentation, or idea what dependencies to respect.

The function has been observed to fail when lines (particularly function definitions wrap across lines). There is also an option of parsing R files, but it's fairly poor especially for (eg. dataframes) that are attached in various ways and the columns directly referenced, or for named arguments in function calls.

function prototype:
[unresolved, assigned, called, ll, assinFn] = matlabParser(fname, MATLABorR, bIgnoreFnBody)

INPUTS:
- fname          - (string) [full] filename
- MATLABorR      - (char) {'m','R'}
- bIgnoreFnBody  - (bool) do not return assigned variables in function body, since these will be inaccessible outside of it. This also assumes that functions will execute and by definition have no unresolved variables.

OUTPUTS:
- unresolved     - (cell string) names of all unresolved variables/functions in file
- assigned       - (cell string) names of all assigned variables/functions in file
- called         - (cell string) names of all called variables/functions in file
- ll             - (double) number of lines in file
- assInFn        - (cell string) if output requested, and bIgnoreFnBody=false, the variables that are assigned only in the function body are removed from the 'assigned' cell and placed in this one.

DEPENDS:
- utils          - (package) [matlab-utils] also under this git account. In fairness, the only dependency is on a slightly modified stack object, which can be found under utils > +base > +objStack.

Example file given attempts to resolve all unresolved references within a given directory. Dependencies are output as node and edge files which may be visualised in Gephi. This file depends more substantially on the utils package.

