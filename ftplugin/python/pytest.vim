" File:        pytest.vim
" Description: Runs the current test Class/Method/Function/File with
"              py.test
" Maintainer:  Alfredo Deza <alfredodeza AT gmail.com>
" License:     MIT
"============================================================================


if exists("g:loaded_pytest") || &cp
  finish
endif


" Global variables for registering next/previous error
let g:pytest_session_errors    = {}
let g:pytest_session_error     = 0
let g:pytest_last_session      = ""
let g:pytest_looponfail        = 0
if !exists("g:pytest_test_dir")
	let g:pytest_test_dir        = 'tests'
endif
if !exists("g:pytest_test_file")
	let g:pytest_test_file       = 'tests.py'
endif

" Process ID of async calls in NeoVim
let s:id                       = 0


function! s:PytestSyntax() abort
  let b:current_syntax = 'pytest'
  syn match PytestPlatform              '\v^(platform(.*))'
  syn match PytestTitleDecoration       "\v\={2,}"
  syn match PytestTitle                 "\v\s+(test session starts)\s+"
  syn match PytestCollecting            "\v(collecting\s+(.*))"
  syn match PytestPythonFile            "\v((.*.py\s+))"
  syn match PytestFooterFail            "\v\s+((.*)(failed|error) in(.*))\s+"
  syn match PytestFooter                "\v\s+((.*)passed in(.*))\s+"
  syn match PytestFailures              "\v\s+(FAILURES|ERRORS)\s+"
  syn match PytestErrors                "\v^E\s+(.*)"
  syn match PytestDelimiter             "\v_{3,}"
  syn match PytestFailedTest            "\v_{3,}\s+(.*)\s+_{3,}"

  hi def link PytestPythonFile          String
  hi def link PytestPlatform            String
  hi def link PytestCollecting          String
  hi def link PytestTitleDecoration     Comment
  hi def link PytestTitle               String
  hi def link PytestFooterFail          String
  hi def link PytestFooter              String
  hi def link PytestFailures            Number
  hi def link PytestErrors              Number
  hi def link PytestDelimiter           Comment
  hi def link PytestFailedTest          Comment
endfunction


function! s:PytestFailsSyntax() abort
  let b:current_syntax = 'pytestFails'
  syn match PytestQDelimiter            "\v\s+(\=\=\>\>)\s+"
  syn match PytestQLine                 "Line:"
  syn match PytestQPath                 "\v\s+(Path:)\s+"
  syn match PytestQEnds                 "\v\s+(Ends On:)\s+"

  hi def link PytestQDelimiter          Comment
  hi def link PytestQLine               String
  hi def link PytestQPath               String
  hi def link PytestQEnds               String
endfunction


function! s:SetExecutable()
    if !exists("g:pytest_executable")
      let g:pytest_executable = "py.test"
    endif
endfunction

function! s:SetExtraFlags()
	if !exists("g:pytest_extraflags")
		let g:pytest_extraflags = ""
	endif
endfunction

function! s:LoopOnFail(type)

    augroup pytest_loop_autocmd
        au!
        if g:pytest_looponfail == 0
            return
        elseif a:type == 'method'
            autocmd! BufWritePost *.py call s:LoopProxy('method')
        elseif a:type == 'class'
            autocmd! BufWritePost *.py call s:LoopProxy('class')
        elseif a:type == 'function'
            autocmd! BufWritePost *.py call s:LoopProxy('function')
        elseif a:type == 'file'
            autocmd! BufWritePost *.py call s:LoopProxy('file')
        endif
    augroup END

endfunction


function! s:LoopProxy(type)
    " Very repetitive function, but allows specific function
    " calling when autocmd is executed
    if g:pytest_looponfail == 1
        if a:type == 'method'
            call s:ThisMethod(0, 'False', [], [])
        elseif a:type == 'class'
            call s:ThisClass(0, 'False', [], [])
        elseif a:type == 'function'
            call s:ThisFunction(0, 'False', [], [])
        elseif a:type == 'file'
            call s:ThisFile(0, 'False', [], [])
        endif

        " FIXME Removing this for now until I can find
        " a way of getting the bottom only on fails
        " Go to the very bottom window
        "call feedkeys("\<C-w>b", 'n')
    else
        au! pytest_loop_autocmd
    endif
endfunction


" Close the Pytest buffer if it is the last one open
function! s:CloseIfLastWindow()
  if winnr("$") == 1
    q
  endif
endfunction


function! s:GoToInlineError(direction)
    let orig_line = line('.')
    let last_line = line('$')

    " Move to the line we need
    let move_to = orig_line + a:direction

    if move_to > last_line
        let move_to = 1
        exe move_to
    elseif move_to <= 1
        let move_to = last_line
        exe move_to
    else
        exe move_to
    endif

    if move_to == 1
        let _num = move_to
    else
        let _num = move_to - 1
    endif

    "  Goes to the current open window that matches
    "  the error path and moves you there. Pretty awesome
    if (len(g:pytest_session_errors) > 0)
        let select_error = g:pytest_session_errors[_num]
        let line_number  = select_error['file_line']
        let error_path   = select_error['file_path']
        let exception    = select_error['exception']
        let error        = select_error['error']

        " Go to previous window
        exe 'wincmd p'
        let file_name    = expand("%:t")
        if error_path =~ file_name
            execute line_number
            execute 'normal! zz'
            exe 'wincmd p'
            let orig_line = _num+1
            exe orig_line
            let message = "Failed test: " . _num . "\t ==>> " . exception . " ". error
            call s:Echo(message, 1)
            return
        else " we might have an error on another file
            let message = "Failed test on different buffer. Skipping..."
            call s:Echo(message, 1)
            exe 'wincmd p'
        endif

    else
        call s:Echo("Failed test list is empty")
    endif
endfunction

function! s:GoToError(direction)
    "   0 goes to first
    "   1 goes forward
    "  -1 goes backwards
    "   2 goes to last
    "   3 goes to the end of current error
    call s:ClearAll()
    let going = "First"
    if (len(g:pytest_session_errors) > 0)
        if (a:direction == -1)
            let going = "Previous"
            if (g:pytest_session_error == 0 || g:pytest_session_error == 1)
                let g:pytest_session_error = 1
            else
                let g:pytest_session_error = g:pytest_session_error - 1
            endif
        elseif (a:direction == 1)
            let going = "Next"
            if (g:pytest_session_error != len(g:pytest_session_errors))
                let g:pytest_session_error = g:pytest_session_error + 1
            endif
        elseif (a:direction == 0)
            let g:pytest_session_error = 1
        elseif (a:direction == 2)
            let going = "Last"
            let g:pytest_session_error = len(g:pytest_session_errors)
        elseif (a:direction == 3)
            if (g:pytest_session_error == 0 || g:pytest_session_error == 1)
                let g:pytest_session_error = 1
            endif
            let select_error = g:pytest_session_errors[g:pytest_session_error]
            let line_number = select_error['file_line']
            let error_path = select_error['file_path']
            let exception = select_error['exception']
            let file_name = expand("%:t")
            if error_path =~ file_name
                execute line_number
            else
                call s:OpenError(error_path)
                execute line_number
            endif
            let message = "End of Failed test: " . g:pytest_session_error . "\t ==>> " . exception
            call s:Echo(message, 1)
            return
        endif

        if (a:direction != 3)
            let select_error = g:pytest_session_errors[g:pytest_session_error]
            let line_number = select_error['line']
            let error_path = select_error['path']
            let exception = select_error['exception']
            let error = select_error['error']
            let file_name = expand("%:t")
            if error_path =~ file_name
                execute line_number
            else
                call s:OpenError(error_path)
                execute line_number
            endif
            let message = going . " Failed test: " . g:pytest_session_error . "\t ==>> " . exception . " " . error
            call s:Echo(message, 1)
            return
        endif
    else
        call s:Echo("Failed test list is empty")
    endif
endfunction


function! s:Echo(msg, ...)
    redraw!
    let x=&ruler | let y=&showcmd
    set noruler noshowcmd
    if (a:0 == 1)
        echo a:msg
    else
        echohl WarningMsg | echo a:msg | echohl None
    endif

    let &ruler=x | let &showcmd=y
endfun


" Always goes back to the first instance
" and returns that if found
function! s:FindPythonObject(obj)
    let orig_line   = line('.')
    let orig_col    = col('.')
    let orig_indent = indent(orig_line)


    if (a:obj == "class")
        let objregexp  = '\v^\s*(.*class)\s+(\w+)\s*'
        let max_indent_allowed = 0
    elseif (a:obj == "method")
        let objregexp = '\v^\s*(.*def)\s+(\w+)\s*\(\_s*(self[^)]*)'
        let max_indent_allowed = 4
    else
        let objregexp = '\v^\s*(.*def)\s+(test\w+)\s*\(\_s*(.*self)@!'
        let max_indent_allowed = orig_indent
    endif

    let flag = "Wb"

    while search(objregexp, flag) > 0
        "
        " Very naive, but if the indent is less than or equal to four
        " keep on going because we assume you are nesting.
        " Do not count lines that are comments though.
        "
        if (indent(line('.')) <= 4) && !(getline(line('.')) =~ '\v^\s*#(.*)')
          if (indent(line('.')) <= max_indent_allowed)
            return 1
          endif
        endif
    endwhile

endfunction


function! s:NameOfCurrentClass()
    let save_cursor = getpos(".")
    normal! $<cr>
    let find_object = s:FindPythonObject('class')
    if (find_object)
        let line = getline('.')
        call setpos('.', save_cursor)
        let match_result = matchlist(line, ' *class \+\(\w\+\)')
        return match_result[1]
    endif
endfunction


function! s:NameOfCurrentMethod()
    normal! $<cr>
    let find_object = s:FindPythonObject('method')
    if (find_object)
        let line = getline('.')
        let match_result = matchlist(line, ' *def \+\(\w\+\)')
        return match_result[1]
    endif
endfunction


function! s:NameOfCurrentFunction()
    normal! $<cr>
    let find_object = s:FindPythonObject('function')
    if (find_object)
        let line = getline('.')
        let match_result = matchlist(line, ' *def \+\(test\w\+\)')
        echom("match_result: " . string(match_result))
        return match_result[1]
    endif
endfunction


function! s:CurrentPath()
    let cwd = fnameescape(expand("%:p"))
    return cwd
endfunction


function! s:ProjectPath()
    let projecttestdir = finddir(g:pytest_test_dir,'.;')
    let projecttestfile = findfile(g:pytest_test_file,'.;')

    if (len(projecttestdir) == 0)
        let projecttestdir = finddir(g:pytest_test_dir, '.;')
    endif

    if(len(projecttestdir) != 0)
        let path = fnamemodify(projecttestdir, ':p:h')
    elseif(len(projecttestfile) != 0)
        let path = fnamemodify(projecttestfile, ':p')
    else
        let path = ''
    endif

    return path
endfunction


function! s:RunInSplitWindow(path)
    let cmd = g:pytest_executable . " --tb=short " . a:path
    let command = join(map(split(cmd), 'expand(v:val)'))
    let winnr = bufwinnr('PytestVerbose.pytest')
    silent! execute  winnr < 0 ? 'botright new ' . 'PytestVerbose.pytest' : winnr . 'wincmd w'
    setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile nowrap number filetype=pytest
    silent! execute 'silent %!'. command
    silent! execute 'resize ' . line('$')
    silent! execute 'nnoremap <silent> <buffer> q :q! <CR>'
    call s:PytestSyntax()
    autocmd! BufEnter LastSession.pytest call s:CloseIfLastWindow()
endfunction


function! s:OpenError(path)
	let winnr = bufwinnr('GoToError.pytest')
	silent! execute  winnr < 0 ? 'botright new ' . ' GoToError.pytest' : winnr . 'wincmd w'
	setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile nowrap number
    silent! execute ":e " . a:path
    silent! execute 'nnoremap <silent> <buffer> q :q! <CR>'
    autocmd! BufEnter LastSession.pytest call s:CloseIfLastWindow()
endfunction


function! s:ShowError()
    call s:ClearAll()
    if (len(g:pytest_session_errors) == 0)
        call s:Echo("No Failed test error from a previous run")
        return
    endif
    if (g:pytest_session_error == 0)
        let error_n = 1
    else
        let error_n = g:pytest_session_error
    endif
    let error_dict = g:pytest_session_errors[error_n]
    if (error_dict['error'] == "")
        call s:Echo("No failed test error saved from last run.")
        return
    endif

	let winnr = bufwinnr('ShowError.pytest')
	silent! execute  winnr < 0 ? 'botright new ' . ' ShowError.pytest' : winnr . 'wincmd w'
	setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile number nowrap
    autocmd! BufEnter LastSession.pytest call s:CloseIfLastWindow()
    silent! execute 'nnoremap <silent> <buffer> q :q! <CR>'
    let line_number = error_dict['file_line']
    let error = error_dict['error']
    let message = "Test Error: " . error
    call append(0, error)
    exe '0'
    exe '0|'
    silent! execute 'resize ' . line('$')
    exe 'wincmd p'
endfunction


function! s:ShowFails(...)
    call s:ClearAll()
    au BufLeave *.pytest echo "" | redraw
    if a:0 > 0
        let gain_focus = a:0
    else
        let gain_focus = 0
    endif
    if (len(g:pytest_session_errors) == 0)
        call s:Echo("No failed tests from a previous run")
        return
    endif
	let winnr = bufwinnr('Fails.pytest')
	silent! execute  winnr < 0 ? 'botright new ' . 'Fails.pytest' : winnr . 'wincmd w'
	setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile nowrap number filetype=pytest
    let blank_line = repeat(" ",&columns - 1)
    exe "normal! i" . blank_line
    hi RedBar ctermfg=white ctermbg=red guibg=red
    match RedBar /\%1l/
    for err in keys(g:pytest_session_errors)
        let err_dict    = g:pytest_session_errors[err]
        let line_number = err_dict['line']
        let exception   = err_dict['exception']
        let path_error  = err_dict['path']
        let ends        = err_dict['file_path']
        let error       = err_dict['error']
        if (path_error == ends)
            let message = printf('Line: %-*u ==>> %-*s %s ==>> %s', 6, line_number, 14, exception, error, path_error)
        else
            let message = printf('Line: %-*u ==>> %-*s %s ==>> %s', 6, line_number, 24, exception, error, ends)
        endif
        let error_number = err + 1
        call setline(error_number, message)
    endfor

	silent! execute 'resize ' . line('$')
    autocmd! BufEnter LastSession.pytest call s:CloseIfLastWindow()
    nnoremap <silent> <buffer> q       :call <sid>ClearAll(1)<CR>
    nnoremap <silent> <buffer> <Enter> :call <sid>ClearAll(1)<CR>
    nnoremap <script> <buffer> <C-n>   :call <sid>GoToInlineError(1)<CR>
    nnoremap <script> <buffer> <down>  :call <sid>GoToInlineError(1)<CR>
    nnoremap <script> <buffer> j       :call <sid>GoToInlineError(1)<CR>
    nnoremap <script> <buffer> <C-p>   :call <sid>GoToInlineError(-1)<CR>
    nnoremap <script> <buffer> <up>    :call <sid>GoToInlineError(-1)<CR>
    nnoremap <script> <buffer> k       :call <sid>GoToInlineError(-1)<CR>
    call s:PytestFailsSyntax()
    exe "normal! 0|h"
    if (! gain_focus)
        exe 'wincmd p'
    else
        call s:Echo("Hit Return or q to exit", 1)
    endif
endfunction


function! s:LastSession()
    call s:ClearAll()
    if (len(g:pytest_last_session) == 0)
        call s:Echo("There is currently no saved last session to display")
        return
    endif
	let winnr = bufwinnr('LastSession.pytest')
	silent! execute  winnr < 0 ? 'botright new ' . 'LastSession.pytest' : winnr . 'wincmd w'
	setlocal buftype=nowrite bufhidden=wipe nobuflisted noswapfile nowrap number filetype=pytest
    let session = split(g:pytest_last_session, '\n')
    call append(0, session)
	silent! execute 'resize ' . line('$')
    silent! execute 'normal! gg'
    autocmd! BufEnter LastSession.pytest call s:CloseIfLastWindow()
    nnoremap <silent> <buffer> q       :call <sid>ClearAll(1)<CR>
    nnoremap <silent> <buffer> <Enter> :call <sid>ClearAll(1)<CR>
    call s:PytestSyntax()
    exe 'wincmd p'
endfunction


function! s:ToggleFailWindow()
	let winnr = bufwinnr('Fails.pytest')
    if (winnr == -1)
        call s:ShowFails()
    else
        silent! execute winnr . 'wincmd w'
        silent! execute 'q'
        silent! execute 'wincmd p'
    endif
endfunction


function! s:ToggleLastSession()
	let winnr = bufwinnr('LastSession.pytest')
    if (winnr == -1)
        call s:LastSession()
    else
        silent! execute winnr . 'wincmd w'
        silent! execute 'q'
        silent! execute 'wincmd p'
    endif
endfunction


function! s:ToggleShowError()
	let winnr = bufwinnr('ShowError.pytest')
    if (winnr == -1)
        call s:ShowError()
    else
        silent! execute winnr . 'wincmd w'
        silent! execute 'q'
        silent! execute 'wincmd p'
    endif
endfunction


function! s:ClearAll(...)
    let current = winnr()
    let bufferL = [ 'Fails.pytest', 'LastSession.pytest', 'ShowError.pytest', 'PytestVerbose.pytest' ]
    for b in bufferL
        let _window = bufwinnr(b)
        if (_window != -1)
            silent! execute _window . 'wincmd w'
            silent! execute 'q'
        endif
    endfor

    " Remove any echoed messages
    if (a:0 == 1)
        " Try going back to our starting window
        " and remove any left messages
        call s:Echo('')
        silent! execute 'wincmd p'
    else
        execute current . 'wincmd w'
    endif
endfunction


function! s:ResetAll()
    " Resets all global vars
    let g:pytest_session_errors    = {}
    let g:pytest_session_error     = 0
    let g:pytest_last_session      = ""
    let g:pytest_looponfail        = 0
endfunction


function! s:RunPyTest(path, ...) abort
    let parametrized = 0
    let extra_flags = ''
    let job_id = get(b:, 'job_id')

    if !exists("g:pytest_use_async")
      let s:pytest_use_async=1
    else
      let s:pytest_use_async=g:pytest_use_async
    endif

    if (a:0 > 0)
      let parametrized = a:1
      if len(a:2)
        let extra_flags = a:2
      endif
    endif

    let g:pytest_last_session = ""

    if (len(parametrized) && parametrized != "0")
        let cmd = g:pytest_executable . " -k " . parametrized . " " . extra_flags . " " . g:pytest_extraflags . " --tb=short " . a:path
    else
        let cmd = g:pytest_executable . " " . extra_flags . " " . g:pytest_extraflags . " --tb=short " . a:path
    endif

    " NeoVim support
    if has('nvim')
      if s:id
        silent! call jobstop(s:id)
      endif

      let tempfile = fnameescape(tempname())

      " If the directory for the temp files does not exist go
      " ahead and create one for us
      let temp_dir_location = fnamemodify(tempname(),":p:h:")
      if !exists(temp_dir_location)
        call system('mkdir ' . temp_dir_location)
      endif

      let s:cmdline =  cmd . " > " . tempfile

      let s:id = jobstart(s:cmdline, {
            \ 'tempfile':  tempfile,
            \ 'on_exit':   function('s:HandleOutputNeoVim') })
      return
    endif

    " Vim 8 support
    if v:version >= 800 && s:pytest_use_async == 1
      if type(job_id) != type(0)
        call job_stop(job_id)
      endif
      let b:job_id = job_start(cmd, {'close_cb': 'CloseHandler'})

      return
    endif

    let stdout = system(cmd)
    call s:HandleOutput(stdout)
endfunction


func! CloseHandler(channel)
  let stdout = ""
  let stderr = ""
  while ch_status(a:channel, {'part': 'out'}) == 'buffered'
    let stdout = stdout . ch_read(a:channel, {'part': 'out'}) . "\n"
  endwhile
  while ch_status(a:channel, {'part': 'err'}) == 'buffered'
    let stderr = stderr . ch_read(a:channel, {'part': 'err'}) . "\n"
  endwhile

  call s:HandleOutput(stdout . stderr)
endfunc


function! s:HandleOutputNeoVim(...) dict
    let stdout = join(readfile(self.tempfile), "\n")
    call delete(self.tempfile)
    call s:HandleOutput(stdout)
endfunction


function! s:HandleOutput(stdout)
    let stdout = a:stdout

    " if py.test insists in giving us color, sanitize the output
    " note that ^[ is really:
    " Ctrl-V Ctrl-[
    let out = substitute(stdout, '[\d\+m', '', 'g')

    " Pointers and default variables
    let g:pytest_session_errors = {}
    let g:pytest_session_error  = 0
    let g:pytest_last_session   = stdout

    for w in split(stdout, '\n')
        if w =~ '\v\=\=\s+\d+ passed in'
            call s:ParseSuccess(out)
            let g:pytest_looponfail = 0
            return
        elseif w =~ '\v\s+(FAILURES)\s+'
            call s:ParseFailures(out)
            return
        elseif w =~ '\v\s+(ERRORS)\s+'
            call s:ParseErrors(out)
            return
        " conftest and plugin errors break all parsing
        elseif w =~ '\v^E\s+\w+:\s+'
            call s:ParseError(out)
            return
        elseif w =~ '\v^(.*)\s*ERROR:\s+'
            call s:ParseError(out)
            return
            call s:RedBar()
            echo g:pytest_executable . " had an Error, see :Pytest session for more information"
            if exists('$VIRTUAL_ENV')
              if !executable($VIRTUAL_ENV . "/bin/py.test")
                echo repeat("*", 80)
                echo " Detected an activated virtualenv but py.test was not found"
                echo " Make sure py.test is installed in the current virtualenv"
                echo " and present at:"
                echo " "
                echo "    " . $VIRTUAL_ENV . "/bin/py.test"
                echo " "
              endif
            endif
            return
        elseif w =~ '\v^(.*)\s*INTERNALERROR'
            call s:RedBar()
            echo g:pytest_executable . " had an InternalError, see :Pytest session for more information"
            return
        endif
    endfor
    call s:ParseSuccess(out)

    " If looponfail is set we no longer need it
    " So clear the autocomand and set the global var to 0
    let g:pytest_looponfail = 0
    call s:LoopOnFail(0)
endfunction


function! s:ParseFailures(stdout)
    " Pointers and default variables
    let failed = 0
    let errors = {}
    let error = {}
    let error_number = 0
    let pytest_error = ""
    let current_file = expand("%:t")
    let file_regex =  '\v(^' . current_file . '|/' . current_file . ')'
    let error['line'] = ""
    let error['path'] = ""
    let error['exception'] = ""

    " Loop through the output and build the error dict
    for w in split(a:stdout, '\n')
        if w =~ '\v\s+(FAILURES)\s+'
            let failed = 1
        elseif w =~ '\v^(.*)\.py:(\d+):'
            if w =~ file_regex
                let match_result = matchlist(w, '\v:(\d+):')
                let error.line = match_result[1]
                let file_path = matchlist(w, '\v(.*.py):')
                let error.path = file_path[1]
            elseif w !~ file_regex
                " Because we have missed out on actual line and path
                " add them here to both file_line and line and file_path and
                " path so that reporting works
                let match_result = matchlist(w, '\v:(\d+):')
                let error.file_line = match_result[1]
                let error.line = match_result[1]
                let file_path = matchlist(w, '\v(.*.py):')
                let error.file_path = file_path[1]
                let error.path = file_path[1]
            endif
        elseif w =~  '\v^E\s+\w+(.*)\s*'
            let split_error = split(w, "E ")
            let actual_error = substitute(split_error[0],'\v^\s+|\s+$',"","g")
            let match_error = matchlist(actual_error, '\v(\w+):\s+(.*)')
            if (len(match_error))
                let error.exception = match_error[1]
                let error.error = match_error[2]
            elseif (len(split(actual_error, ' ')) == 1)
                " this means that we just got an exception with
                " no error message
                let error.exception = actual_error
                let error.error = ""
            else
                let error.exception = "AssertionError"
                let error.error = actual_error
            endif
        elseif w =~ '\v^(.*)\s*ERROR:\s+'
            let pytest_error = w
        endif

        " At the end of the loop make sure we append the failure parsed to the
        " errors dictionary
        if ((error.line != "") && (error.path != "") && (error.exception != ""))
            try
                let end_file_path = error['file_path']
            catch /^Vim\%((\a\+)\)\=:E/
                let error.file_path = error.path
                let error.file_line = error.line
            endtry
            let error_number = error_number + 1
            let errors[error_number] = error
            let error = {}
            let error['line'] = ""
            let error['path'] = ""
            let error['exception'] = ""
        endif
    endfor

    " Display the result Bars
    if (failed == 1)
        let g:pytest_session_errors = errors
        call s:ShowFails(1)
    elseif (failed == 0 && pytest_error == "")
        call s:GreenBar()
    elseif (pytest_error != "")
        call s:RedBar()
        echo g:pytest_executable . " " . pytest_error
    endif
endfunction

function! s:ParseError(stdout)
  " Unlike ParseErrors, this will try to inspect a (generally) fatal error
  " when running pytest. The report for an error looks similar to:
  " ============================= test session starts ==============================
  " platform darwin -- Python 2.7.14, pytest-3.4.1, py-1.5.2, pluggy-0.6.0
  " rootdir: /Users/alfredo/vim/pytest.vim/tests, inifile: pytest.ini
  " plugins: inobject-0.0.1
  " collected 0 items / 1 errors
  "
  " ==================================== ERRORS ====================================
  " ________________ ERROR collecting fixtures/test_import_error.py ________________
  " ImportError while importing test module '/Users/alfredo/vim/pytest.vim/tests/fixtures/test_import_error.py'.
  " Hint: make sure your test modules/packages have valid Python names.
  " Traceback:
  " test_import_error.py:1: in <module>
  "     import DoesNotExistModule
  " E   ImportError: No module named DoesNotExistModule
  " !!!!!!!!!!!!!!!!!!! Interrupted: 1 errors during collection !!!!!!!!!!!!!!!!!!!!
  " =========================== 1 error in 0.12 seconds ============================

    " Pointers and default variables
    let failed = 1
    let errors = {}
    let error = {}
    let no_tests_found = 0
    " Loop through the output and build the error dict

    for w in split(a:stdout, '\n')
        if w =~ '\v^E\s+(File)'
            let match_line_no = matchlist(w, '\v\s+(line)\s+(\d+)')
            let error['line'] = match_line_no[2]
            let error['file_line'] = match_line_no[2]
            let split_file = split(w, "E ")
            let match_file = matchlist(split_file[0], '\v"(.*.py)"')
            let error['file_path'] = match_file[1]
            let error['path'] = match_file[1]
        elseif w =~ '\v^(.*)\.py:(\d+)'
            let match_result = matchlist(w, '\v:(\d+)')
            let error.line = match_result[1]
            let file_path = matchlist(w, '\v(.*.py):')
            let error.path = file_path[1]
            let error.file_path = file_path[1]
        elseif w =~ '\v^ERROR:\s+not\s+found'
          let message = "No valid test names found. No tests ran. See :Pytest session"
          return s:WarningMessage(message)
        endif
        if w =~ '\v^E\s+(\w+):\s+'
            let split_error = split(w, "E ")
            let match_error = matchlist(split_error[0], '\v(\w+):')
            let error['exception'] = match_error[1]
            let actual_error = split(split_error[0], match_error[0])[1]
            let error.error = substitute(actual_error,"^\\s\\+\\|\\s\\+$","","g")
        endif
    endfor

    let errors[1] = error

    let g:pytest_session_errors = errors
    call s:ShowFails(1)
endfunction


function! s:ParseErrors(stdout)
    " Pointers and default variables
    let failed = 0
    let errors = {}
    let error = {}
    " Loop through the output and build the error dict

    for w in split(a:stdout, '\n')
       if w =~ '\v\s+ERROR\s+collecting'
            call s:ParseError(a:stdout)
            return
            call s:RedBar()
            echo g:pytest_executable . " had an error collecting tests, see :Pytest session for more information"
            return

        elseif w =~ '\v\s+(ERRORS)\s+'
            let failed = 1
        elseif w =~ '\v^E\s+(File)\s+'
            let match_line_no = matchlist(w, '\v\s+(line)\s+(\d+)')
            let error['line'] = match_line_no[2]
            let error['file_line'] = match_line_no[2]
            let split_file = split(w, "E ")
            let match_file = matchlist(split_file[0], '\v"(.*.py)"')
            let error['file_path'] = match_file[1]
            let error['path'] = match_file[1]
        elseif w =~ '\v^(.*)\.py:(\d+)'
            let match_result = matchlist(w, '\v:(\d+)')
            let error.line = match_result[1]
            let file_path = matchlist(w, '\v(.*.py):')
            let error.path = file_path[1]
        endif
        if w =~ '\v^E\s+(\w+):\s+'
            let split_error = split(w, "E ")
            let match_error = matchlist(split_error[0], '\v(\w+):')
            let error['exception'] = match_error[1]
            let flat_error = substitute(split_error[0],"^\\s\\+\\|\\s\\+$","","g")
            let error.error = flat_error
        endif
    endfor
    try
        let end_file_path = error['file_path']
    catch /^Vim\%((\a\+)\)\=:E/
        let error.file_path = error.path
        let error.file_line = error.line
    endtry

    " FIXME
    " Now try to really make sure we have some stuff to pass
    " who knows if we are getting more of these :/ quick fix for now
    let error['exception'] = get(error, 'exception', 'AssertionError')
    let error['error']     = get(error, 'error', 'py.test had an error, please see :Pytest session for more information')
    let errors[1] = error

    " Display the result Bars
    if (failed == 1)
        let g:pytest_session_errors = errors
        call s:ShowFails(1)
    elseif (failed == 0)
        call s:GreenBar()
    endif
endfunction


function! s:ParseSuccess(stdout) abort
    let passed = 0
    let xfailed = 0
    let collected_tests = 0
    let no_tests_ran = 0
    " A passing test (or tests would look like:
    " ========================== 17 passed in 0.43 seconds ===========================
    " this would insert that into the resulting GreenBar but only the
    " interesting portion
    "
    "
" ERROR: not found: /Users/alfredo/vim/pytest.vim/tests/fixtures/test_functions.py::foo
" (no name '/Users/alfredo/vim/pytest.vim/tests/fixtures/test_functions.py::foo' in any of [<Module 'fixtures/test_functions.py'>])
    for w in split(a:stdout, '\n')
        if w =~ '\v^\={14,}\s+\d+\s+passed'
            let passed = matchlist(w, '\v\d+\s+passed(.*)\s+')[0]
        elseif w =~ '\v^\={14,}\s+\d+\s+skipped'
            let passed = matchlist(w, '\v\d+\s+skipped(.*)\s+')[0]
        elseif w =~ '\v^\={14,}\s+no\s+tests\s+ran'
            let no_tests_ran = 1
        elseif w =~ '\v^ERROR:\s+not\s+found'
            let no_tests_ran = 1
        elseif w =~ '\v\s+collected\s+\d+\s+items'
            let collected_tests = matchlist(w, '\v\d+')[0]
        elseif w =~ '\v\s+\d+\s+xfailed'
            let xfailed = matchlist(w, '\v\d+\s+xfailed(.*)\s+')[0]
        endif
    endfor

    " if no tests ran, no need to continue processing
    " TODO make a helper out of this
    if no_tests_ran
      redraw
      let message = collected_tests . " collected tests, no tests ran. See :Pytest session"
      let length = strlen(message) + 1
      hi YellowBar ctermfg=black ctermbg=yellow guibg=#e5e500 guifg=black
      echohl YellowBar
      echon message . repeat(" ",&columns - length)
      echohl
      return
    endif

    " fix this obvious redundancy
    if ( passed || xfailed)
        if passed
          let report = passed
        else
          let report = xfailed
        endif
        redraw
        let length = strlen(report) + 1
        let default_showcmd = &showcmd
        " The GUI looks too bright with plain green as a background
        " so make sure we use a solarized-like green and set the foreground
        " to black
        set noshowcmd
        hi GreenBar ctermfg=black ctermbg=green guibg=#719e07 guifg=black
        "hi GreenBar ctermfg=black ctermbg=green guibg=green guifg=black
        echohl GreenBar
        echon report . repeat(" ",&columns - length)
        echohl
        if default_showcmd
          set showcmd
        endif
    else
        " At this point we have parsed the output and have not been able to
        " determine if the test run has had pytest errors, or faillures,
        " passing tests, or even skipped ones. So something must be weird with
        " the output. Instead of defaulting to 'All tests passed!' warn the
        " user that we were unable to parse the output.
        redraw
        let message = "Unable to parse output. If using a plugin that alters the default output, consider disabling it. See :Pytest session"
        let length = strlen(message) + 1
        hi YellowBar ctermfg=black ctermbg=yellow guibg=#e5e500 guifg=black
        echohl YellowBar
        echon message . repeat(" ",&columns - length)
        echohl
    endif
endfunction


function! s:RedBar()
    redraw
    hi RedBar ctermfg=white ctermbg=red guibg=red
    echohl RedBar
    echon repeat(" ",&columns - 1)
    echohl
endfunction


function! s:GreenBar()
    redraw
    hi GreenBar ctermfg=black ctermbg=green guibg=green
    echohl GreenBar
    echon "All tests passed." . repeat(" ",&columns - 18)
    echohl
endfunction


function! s:WarningMessage(message)
    redraw
    let length = strlen(a:message) + 1
    hi YellowBar ctermfg=black ctermbg=yellow guibg=#e5e500 guifg=black
    echohl YellowBar
    echon a:message . repeat(" ",&columns - length)
    echohl
    return
endfunction


function! s:ThisMethod(verbose, ...)
    let extra_flags = ''
    let save_cursor = getpos('.')
    call s:ClearAll()
    let m_name  = s:NameOfCurrentMethod()
    let is_parametrized = s:IsParametrized(line('.'))

    let c_name  = s:NameOfCurrentClass()
    let abspath = s:CurrentPath()
    if (strlen(m_name) == 1)
        call setpos('.', save_cursor)
        call s:Echo("Unable to find a matching method for testing")
        return
    elseif (strlen(c_name) == 1)
        call setpos('.', save_cursor)
        call s:Echo("Unable to find a matching class for testing")
        return
    endif

    " If we didn't error, still, save the cursor so we are back
    " to the original position
    call setpos('.', save_cursor)

    if is_parametrized
        let path =  abspath . "::" . c_name
        let parametrized_flag = m_name
        let message = g:pytest_executable . " ==> Running test for parametrized method " . m_name
    else
        let path =  abspath . "::" . c_name . "::" . m_name
        let parametrized_flag = "0"
        let message = g:pytest_executable . " ==> Running test for method " . m_name
    endif

    call s:Echo(message, 1)
    if len(a:2)
      call s:Delgado(path, a:2, message)
      return
    endif

    if len(a:3)
        let extra_flags = join(a:3, ' ')
    endif

    if ((a:1 == '--pdb') || (a:1 == '-s'))
        call s:Pdb(path, a:1, parametrized_flag, extra_flags)
        return
    endif

    if (a:verbose == 1)
        call s:RunInSplitWindow(path)
    else
       call s:RunPyTest(path, parametrized_flag, extra_flags)
    endif
endfunction


function! s:IsParametrized(line)
    " Get to the previous line where the decorator lives
    let line = a:line -1
    " if it is whitespace or there is nothing there, return
    if (getline(line) =~ '^\\s*\\S')
        return 0
    endif

    " now keep searching back as long as there aren't any other
    " empty lines
    while (getline(line) !~ '^\\s*\\S')
        if (getline(line) =~ '\v^(.*\@[a-zA-Z])')
            " this is the only situation where we are decorated, so check
            " to see if this is really pytest.mark.parametrized or just some
            " other decorator
            let decorated_line = getline(line)
            if (decorated_line =~ '\v(.*)parametrize(.*)') && (decorated_line !~ '\v^\s*#(.*)')
                return 1
            endif
        elseif (getline(line) =~ '\v^\s*(.*def)\s+(\w+)\s*\(\s*')
            " so we found either a function or a class, therefore, no way we have
            " a decorator
            return 0
        elseif (line < 1)
            " we went all the way to the top of the file, no need to keep going
            return 0
        endif
        let line = line - 1
    endwhile

endfunction


function! s:ThisFunction(verbose, ...)
    let extra_flags = ''
    let save_cursor = getpos('.')
    call s:ClearAll()
    let c_name      = s:NameOfCurrentFunction()
    let is_parametrized = s:IsParametrized(line('.'))
    let abspath     = s:CurrentPath()
    if (strlen(c_name) == 1)
        call setpos('.', save_cursor)
        call s:Echo("Unable to find a matching function for testing")
        return
    endif

    " If we didn't error, still, save the cursor so we are back
    " to the original position
    call setpos('.', save_cursor)

    let message  = g:pytest_executable . " ==> Running tests for function " . c_name
    call s:Echo(message, 1)

    if is_parametrized
        let path = abspath
    else
        let path = abspath . "::" . c_name
    endif

    if len(a:2)
      call s:Delgado(path, a:2, message)
      return
    endif

    if len(a:3)
        let extra_flags = join(a:3, ' ')
    endif

    if ((a:1 == '--pdb') || (a:1 == '-s'))
        call s:Pdb(path, a:1, c_name, extra_flags)
        return
    endif

    if (a:verbose == 1)
        call s:RunInSplitWindow(path)
    else
        call s:RunPyTest(path, c_name, extra_flags)
    endif
endfunction


function! s:ThisClass(verbose, ...)
    let extra_flags = ''
    let save_cursor = getpos('.')
    call s:ClearAll()
    let c_name      = s:NameOfCurrentClass()
    let abspath     = s:CurrentPath()
    if (strlen(c_name) == 1)
        call setpos('.', save_cursor)
        call s:Echo("Unable to find a matching class for testing")
        return
    endif
    let message  = g:pytest_executable . " ==> Running tests for class " . c_name
    call s:Echo(message, 1)

    let path = abspath . "::" . c_name
    if len(a:2)
      call s:Delgado(path, a:2, message)
      return
    endif

    if ((a:1 == '--pdb') || (a:1 == '-s'))
        call s:Pdb(path, a:1, 0, extra_flags)
        return
    endif

    if len(a:3)
        let extra_flags = join(a:3, ' ')
    endif

    if (a:verbose == 1)
        call s:RunInSplitWindow(path, extra_flags)
    else
        call s:RunPyTest(path, 0, extra_flags)
    endif
endfunction


function! s:ThisFile(verbose, ...)
    let extra_flags = ''
    call s:ClearAll()
    let message = g:pytest_executable . " ==> Running tests for entire file"
    call s:Echo(message, 1)
    let abspath = s:CurrentPath()
    if len(a:2)
      call s:Delgado(abspath, a:2, message)
      return
    endif

    if ((a:1 == '--pdb') || (a:1 == '-s'))
        call s:Pdb(abspath, a:1, 0, extra_flags)
        return
    endif

    if len(a:3)
        let extra_flags = join(a:3, ' ')
    endif

    if (a:verbose == 1)
        call s:RunInSplitWindow(abspath)
    else
        call s:RunPyTest(abspath, 0, extra_flags)
    endif
endfunction

function! s:ThisProject(verbose, ...)
    let extra_flags = ''
    call s:ClearAll()
    let message = g:pytest_executable . " ==> Running tests for entire project"
    call s:Echo(message, 1)
    let abspath = s:ProjectPath()

    if len(abspath) <= 0
        call s:RedBar()
        echo "There are no tests defined for this project"
        return
    endif

    if len(a:3)
        let extra_flags = join(a:3, ' ')
    endif

    if ((a:1 == '--pdb') || (a:1 == '-s'))
        call s:Pdb(abspath, a:1, 0, extra_flags)
        return
    endif

    if (a:verbose == 1)
        call s:RunInSplitWindow(abspath)
    else
        call s:RunPyTest(abspath, 0, extra_flags)
    endif
endfunction


function! s:Pdb(path, ...)
    let extra_flags = ''
    if (a:0 >= 2)
      let parametrized = a:2
      if len(a:3)
        let extra_flags = a:3
      endif
    endif

    if (len(parametrized) && parametrized != "0")
        let pdb_command = g:pytest_executable . " " . a:1 . " -k " . parametrized . " " . extra_flags . " " . a:path
    else
        let pdb_command = g:pytest_executable . " " . a:1 . " " . extra_flags . " " . a:path
    endif

    if has('terminal')
        exe ":term " . pdb_command
    elseif has('nvim')
        exe ":terminal! " . pdb_command
    else
        exe ":!" . pdb_command
    endif
endfunction


function! s:Delgado(path, arguments, message)
    let args = a:arguments[1:]
    let str_args = ""
    if len(args)
      for item in args
        let str_args = str_args . '\"' . item .'\",'
      endfor
    endif
    let args_as_list = '[' . str_args . '\"' . a:path . '\"]'
    let json_arg = '{\"py.test\" :'. args_as_list . '}'
    let command = ":!" . "echo \"" . json_arg . "\"| nc -U /tmp/pytest.sock" . " &"
    " If debugging this, uncomment the next line
    " so that it echoes to :messages
    " echom command
    silent! exe command
    if !has("gui_running")
        call s:Echo(a:message, 1)
    endif
endfunction


function! s:Version()
    call s:Echo("pytest.vim version 1.1.5", 1)
endfunction


function! s:Completion(ArgLead, CmdLine, CursorPos)
    let result_order = "first\nlast\nnext\nprevious\n"
    let test_objects = "class\nmethod\nfunction\nfile\nproject\nprojecttestwd\n"
    let optional     = "verbose\nlooponfail\nclear\n"
    let reports      = "fails\nerror\nsession\nend\n"
    let pyversion    = "version\n"
    let pdb          = "--pdb\n-s\n"
    return test_objects . result_order . reports . optional . pyversion . pdb
endfunction


function! s:Proxy(action, ...)
    call s:SetExecutable()
    if (executable(g:pytest_executable . "") == 0)
        call s:Echo(g:pytest_executable . " not found. This plugin needs py.test installed and accessible")
        return
    endif

    " Some defaults
    let verbose = 0
    let pdb     = 'False'
    let looponfail = 0
    let delgado = []
    let extra_flags = []
    let has_extra_flags = 0

    if (a:0 > 0)
        if (a:1 == 'verbose')
            let verbose = 1
        elseif (a:1 == '--pdb')
            let pdb = '--pdb'
        elseif (a:1 == '-s')
            let pdb = '-s'
        elseif (a:1 == 'looponfail')
            let g:pytest_looponfail = 1
            let looponfail = 1
        elseif (a:1 == 'delgado')
            let delgado = a:000
        else
          let extra_flags = a:000[0:]
          let has_extra_flags = 1
        endif
        if !has_extra_flags
            let extra_flags = a:000[1:]
        endif
    endif
    if (a:action == "class")
        if looponfail == 1
            call s:LoopOnFail(a:action)
            call s:ThisClass(verbose, pdb, delgado, extra_flags)
        else
            call s:ThisClass(verbose, pdb, delgado, extra_flags)
        endif
    elseif (a:action == "method")
        if looponfail == 1
            call s:LoopOnFail(a:action)
            call s:ThisMethod(verbose, pdb, delgado, extra_flags)
        else
            call s:ThisMethod(verbose, pdb, delgado, extra_flags)
        endif
    elseif (a:action == "function")
        if looponfail == 1
            call s:LoopOnFail(a:action)
            call s:ThisFunction(verbose, pdb, delgado, extra_flags)
        else
            call s:ThisFunction(verbose, pdb, delgado, extra_flags)
        endif
    elseif (a:action == "file")
        if looponfail == 1
            call s:LoopOnFail(a:action)
            call s:ThisFile(verbose, pdb, delgado, extra_flags)
        else
            call s:ThisFile(verbose, pdb, delgado, extra_flags)
        endif
    elseif (a:action == "project" )
        if looponfail ==1
            call s:LoopOnFail(a:action)
            call s:ThisProject(verbose, pdb, delgado, extra_flags)
        else
            call s:ThisProject(verbose, pdb,delgado, extra_flags)
        endif
    elseif (a:action == "projecttestwd")
        let projecttests = s:ProjectPath()
        call s:Echo(projecttests)
    elseif (a:action == "fails")
        call s:ToggleFailWindow()
    elseif (a:action == "next")
        call s:GoToError(1)
    elseif (a:action == "previous")
        call s:GoToError(-1)
    elseif (a:action == "first")
        call s:GoToError(0)
    elseif (a:action == "last")
        call s:GoToError(2)
    elseif (a:action == "end")
        call s:GoToError(3)
    elseif (a:action == "session")
        call s:ToggleLastSession()
    elseif (a:action == "error")
        call s:ToggleShowError()
    elseif (a:action == "clear")
        call s:ClearAll()
        call s:ResetAll()
    elseif (a:action == "version")
        call s:Version()
    else
        call s:Echo("Not a valid Pytest option ==> " . a:action)
    endif
endfunction


command! -nargs=+ -complete=custom,s:Completion Pytest call s:Proxy(<f-args>)
