" vim:foldmethod=marker:fen:
scriptencoding utf-8
" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}

" Script variables {{{
let s:PRAGMA_IGNORE_SPACES = 'ignore-spaces'
lockvar s:PRAGMA_IGNORE_SPACES
let s:PRAGMA_LEADER_MACRO = 'leader-macro'
lockvar s:PRAGMA_LEADER_MACRO
let s:PRAGMA_WARNINGS_MODE = 'warnings-mode'
lockvar s:PRAGMA_WARNINGS_MODE

let s:pragmas = {
\   s:PRAGMA_IGNORE_SPACES : 0,
\   s:PRAGMA_LEADER_MACRO  : 0,
\   s:PRAGMA_WARNINGS_MODE : 0,
\}
let s:GROUP_PRAGMAS = {
\   'all': 'emap#available_pragmas()',
\   'warnings': printf('filter(emap#available_pragmas(), %s)', string('v:val =~# "^warnings-"')),
\}
lockvar s:GROUP_PRAGMAS

let s:vimrc_sid = -1

function! s:SID() "{{{
    return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfunction "}}}
let s:EMAP_SNR = printf("<SNR>%d_", s:SID())
lockvar s:EMAP_SNR

" s:map_dict {{{
let s:map_dict = {'stash': {}}

function! s:map_dict_new() "{{{
    return deepcopy(s:map_dict)
endfunction "}}}

function! s:map_dict.map(mode, map_info_options, lhs, rhs) dict "{{{
    let self.stash[a:mode . a:lhs] =
    \   s:map_dict_create_rhs(a:rhs, a:map_info_options)
endfunction "}}}
function! s:map_dict.unmap(mode, map_info_options, lhs) dict "{{{
    unlet self.stash[a:mode . a:lhs]
endfunction "}}}
function! s:map_dict_create_rhs(rhs, map_info_options) "{{{
    " NOTE: This function may be frequently called by :for.
    " And `a:map_info_options` may be same object during :for.
    return extend(
    \   a:map_info_options,
    \   {'_rhs': a:rhs},
    \   'keep',
    \)
endfunction "}}}

function! s:map_dict.maparg(lhs, mode) dict "{{{
    " NOTE: a:mode is only one character.
    return get(self.stash, a:mode . a:lhs, {'_rhs': ''})._rhs
endfunction "}}}

lockvar s:map_dict
" }}}

let s:named_map = s:map_dict_new()
let s:macro_map = s:map_dict_new()

let s:ex_commands = {
\   'DefMacroMap': {'opt': '-nargs=*', 'def': 'call s:cmd_defmacromap(<cmdname>, <q-args>)'},
\   'DefMacroUnmap': {'opt': '-nargs=*', 'def': 'call s:cmd_defmacrounmap(<cmdname>, <q-args>)'},
\   'DefMap': {'opt': '-nargs=*', 'def': 'call s:cmd_defmap(<cmdname>, <q-args>)'},
\   'DefUnmap': {'opt': '-nargs=*', 'def': 'call s:cmd_defunmap(<cmdname>, <q-args>)'},
\   'Map': {'opt': '-nargs=*', 'def': 'call s:cmd_map(<cmdname>, <q-args>)'},
\   'Unmap': {'opt': '-nargs=*', 'def': 'call s:cmd_unmap(<cmdname>, <q-args>)'},
\   'SetPragmas': {'opt': '-bar -nargs=+', 'def': 'call emap#set_pragmas([<f-args>])'},
\   'UnsetPragmas': {'opt': '-bar -nargs=+', 'def': 'call emap#unset_pragmas([<f-args>])'},
\}
" }}}

" Functions {{{

" Wrapper functions for built-ins.
function! s:matchstr(str, regex) "{{{
    return call('matchstr', [a:str, a:regex . '\C'] + a:000)
endfunction "}}}
function! s:matchlist(str, regex, ...) "{{{
    return call('matchlist' [a:str, a:regex . '\C'] + a:000)
endfunction "}}}


" Utilities
function! s:error(...) "{{{
    if a:0
        echohl ErrorMsg
        echomsg join(a:000)
        echohl None
    else
        call s:error(substitute(v:exception, '^Vim(\w\+):', '', ''))
    endif
endfunction "}}}

function! s:errorf(msg, ...) "{{{
    call s:error(call('printf', [a:msg] + a:000))
endfunction "}}}

function! s:each_char(str) "{{{
    return split(a:str, '\zs')
endfunction "}}}

function! s:skip_spaces(q_args) "{{{
    return substitute(a:q_args, '^[ \t]*', '', '')
endfunction "}}}

function! s:has_elem(list, elem) "{{{
    return !empty(filter(copy(a:list), 'v:val ==# a:elem'))
endfunction "}}}

function! s:has_all_of(list, elem) "{{{
    " a:elem is List:
    "   a:list has a:elem[0] && a:list has a:elem[1] && ...
    " a:elem is not List:
    "   a:list has a:elem

    if type(a:elem) == type([])
        for i in a:elem
            if !s:has_elem(a:list, i)
                return 0
            endif
        endfor
        return 1
    else
        return s:has_elem(a:list, a:elem)
    endif
endfunction "}}}

function! s:has_one_of(list, elem) "{{{
    " a:elem is List:
    "   a:list has a:elem[0] || a:list has a:elem[1] || ...
    " a:elem is not List:
    "   a:list has a:elem

    if type(a:elem) == type([])
        for i in a:elem
            if s:has_elem(a:list, i)
                return 1
            endif
        endfor
        return 0
    else
        return s:has_elem(a:list, a:elem)
    endif
endfunction "}}}



function! s:add_pragmas(options) "{{{
    return extend(copy(a:options), {
    \   'pragmas': filter(keys(s:pragmas), 's:pragmas[v:val]')
    \}, 'keep')
endfunction "}}}

function! s:opt_has(options, name) "{{{
    return get(a:options, a:name, 0)
endfunction "}}}

function! s:pragma_has(options, name) "{{{
    if a:name == s:PRAGMA_IGNORE_SPACES
        " Do not apply `ignore-spaces` when -`expr` is specified.
        return s:has_elem(get(a:options, 'pragmas', []), a:name)
        \   && !s:opt_has(a:options, 'expr')
    else
        return s:has_elem(get(a:options, 'pragmas', []), a:name)
    endif
endfunction "}}}

function! s:convert_options(options) "{{{
    " Convert to Vim's :map option notation.
    return
    \   (get(a:options, 'expr', 0) ? '<expr>' : '')
    \   . (get(a:options, 'buffer', 0) ? '<buffer>' : '')
    \   . (get(a:options, 'silent', 0) ? '<silent>' : '')
    \   . (get(a:options, 'special', 0) ? '<special>' : '')
    \   . (get(a:options, 'script', 0) ? '<script>' : '')
    \   . (get(a:options, 'unique', 0) ? '<unique>' : '')
endfunction "}}}


" Errors
function! s:parse_error(msg) "{{{
    return 'parse error: ' . a:msg
endfunction "}}}

function! s:argument_error(msg) "{{{
    return 'argument error: ' . a:msg
endfunction "}}}


" Mode
function! s:is_mode_char(char) "{{{
    return a:char =~# '^[nvoiclxs]$'
endfunction "}}}
function! s:get_all_modes() "{{{
    return 'nvoiclxs'
endfunction "}}}

function! s:filter_modes(modes, options) "{{{
    let ret = []
    for m in s:each_char(a:modes)
        if s:is_mode_char(m)
            call add(ret, m)
        elseif s:pragma_has(a:options, s:PRAGMA_WARNINGS_MODE)
            call s:errorf("'%s' is not available mode.", m)
        endif
    endfor
    return ret
endfunction "}}}


" For ex commands
function! emap#load(...) "{{{
    " TODO autoload functions for ex commands.

    for cmdname in (a:0 ? a:000 : keys(s:ex_commands))
        if type(cmdname) == type([])
            if len(cmdname) < 2
                echohl ErrorMsg
                echomsg 'Invalid arguments for emap#load(). See :help emap#load()'
                echohl None
                return
            endif
            call s:define_command(cmdname[0], 1, cmdname[1])
        else
            call s:define_command(cmdname, 1)
        endif
    endfor
endfunction "}}}

function! s:define_command(cmdname, force, ...) "{{{
    if !has_key(s:ex_commands, a:cmdname)
        echohl ErrorMsg
        echomsg a:cmdname . ": Unknown command"
        echohl None
        return
    endif

    execute
    \   'command' . (a:force ? '!' : '')
    \   s:ex_commands[a:cmdname].opt
    \   (a:0 ? a:1 : a:cmdname)
    \   substitute(s:ex_commands[a:cmdname].def, '<cmdname>'.'\C', string(a:cmdname), '')
endfunction "}}}

function! s:map_command(cmdname, q_args, convert_lhs_fn, dict_map) "{{{
    try
        let map_info = s:parse_args(a:q_args)
    catch /^parse error:/
        call s:errorf("%s: %s", a:cmdname, v:exception)
        return
    endtry

    for m in s:filter_modes(
    \   (map_info.modes != '' ? map_info.modes : s:get_all_modes()),
    \   map_info.options
    \)
        let args = [
        \   m,
        \   map_info.options,
        \   {a:convert_lhs_fn}(m, map_info),
        \   (map_info.rhs == '' ? '' : emap#compile_map(map_info.rhs, m, map_info.options)),
        \]
        try
            " List or register mappings with :map command.
            execute call('s:get_map_excmd', args)
            " Save this mapping to `a:dict_map` indivisually.
            " Because Vim can't look up lhs with <SID> correctly by maparg().
            if !empty(a:dict_map)
                call call(a:dict_map.map, args, a:dict_map)
            endif
        catch
            call s:error()
        endtry
    endfor
endfunction "}}}
function! s:unmap_command(cmdname, q_args, convert_lhs_fn, dict_map) "{{{
    try
        let map_info = s:parse_args(a:q_args)
    catch /^parse error:/
        call s:errorf("%s: %s", a:cmdname, v:exception)
        return
    endtry

    for m in s:filter_modes(map_info.modes, map_info.options)
        let args = [
        \   m,
        \   map_info.options,
        \   {a:convert_lhs_fn}(m, map_info),
        \]
        try
            execute call('s:get_unmap_excmd', args)
            if !empty(a:dict_map)
                call call(a:dict_map.unmap, args, a:dict_map)
            endif
        catch
            call s:error()
        endtry
    endfor
endfunction "}}}

function! s:convert_defmap(mode, map_info) "{{{
    return s:get_snr_named_lhs(a:map_info.lhs)
endfunction "}}}
function! s:convert_defmacromap(mode, map_info) "{{{
    return s:get_snr_macro_lhs(a:map_info.lhs)
endfunction "}}}
function! s:convert_map(mode, map_info) "{{{
    return emap#compile_map(a:map_info.lhs, a:mode, a:map_info.options)
endfunction "}}}


function! s:cmd_defmacromap(cmdname, q_args) "{{{
    return s:map_command(a:cmdname, a:q_args, 's:convert_defmacromap', s:macro_map)
endfunction "}}}
function! s:cmd_defmap(cmdname, q_args) "{{{
    return s:map_command(a:cmdname, a:q_args, 's:convert_defmap', s:named_map)
endfunction "}}}
function! s:cmd_map(cmdname, q_args) "{{{
    return s:map_command(a:cmdname, a:q_args, 's:convert_map', {})
endfunction "}}}


function! s:cmd_defmacrounmap(cmdname, q_args) "{{{
    return s:unmap_command(a:cmdname, a:q_args, 's:convert_defmacromap', s:macro_map)
endfunction "}}}
function! s:cmd_defunmap(cmdname, q_args) "{{{
    return s:unmap_command(a:cmdname, a:q_args, 's:convert_defmap', s:named_map)
endfunction "}}}
function! s:cmd_unmap(cmdname, q_args) "{{{
    return s:unmap_command(a:cmdname, a:q_args, 's:convert_map', {})
endfunction "}}}


" Parser for ex commands.
function! s:parse_modes(q_args) "{{{
    let mode_arg = s:matchstr(a:q_args, '^\[[^\[\]]\+\]')
    let rest  = strpart(a:q_args, strlen(mode_arg))
    let modes = mode_arg[1:-2]
    if modes == ''
        throw s:parse_error("empty mode '[...]' argument")
    endif
    return [modes, rest]
endfunction "}}}

function! s:parse_options(q_args) "{{{
    let q_args = a:q_args
    let opt = s:get_default_options()

    while !empty(q_args)
        let [a, rest] = s:parse_one_arg_from_q_args(q_args)
        if a[0] !=# '-'
            break
        endif
        let q_args = rest

        if a ==# '--'
            break
        elseif a[0] ==# '-'
            if a[1:] ==# 'expr'
                let opt.expr = 1
            elseif a[1:] ==# 'remap'
                let opt.noremap = 0
            elseif a[1:] ==# 'buffer'
                let opt.buffer = 1
            elseif a[1:] ==# 'silent'
                let opt.silent = 1
            elseif a[1:] ==# 'special'
                let opt.special = 1
            elseif a[1:] ==# 'script'
                let opt.script = 1
            elseif a[1:] ==# 'force'
                let opt.unique = 0
            else
                throw s:parse_error(printf("unknown option '%s'.", a))
            endif
        endif
    endwhile

    return [opt, q_args]
endfunction "}}}

function! s:get_default_options() "{{{
    " In emap, <unique> and noremap is default.
    return {
    \   'expr': 0,
    \   'buffer': 0,
    \   'silent': 0,
    \   'special': 0,
    \   'script': 0,
    \   'unique': 1,
    \   'noremap': 1,
    \}
endfunction "}}}

function! s:parse_one_arg_from_q_args(q_args) "{{{
    let arg = s:skip_spaces(a:q_args)
    let head = s:matchstr(arg, '^.\{-}[^\\]\ze\([ \t]\|$\)')
    let rest = strpart(arg, strlen(head))
    return [head, rest]
endfunction "}}}

function! s:parse_lhs(q_args) "{{{
    let [lhs, q_args] = s:parse_one_arg_from_q_args(a:q_args)
    call s:validate_lhs(lhs)
    return [lhs, q_args]
endfunction "}}}

function! s:validate_lhs(lhs) "{{{
    if a:lhs == ''
        throw s:parse_error('empty lhs.')
    endif

    let illegal = s:matchstr(a:lhs, '^<\(expr\|buffer\|silent\|special\|script\|unique\)>')
    if illegal != ''
        throw s:parse_error(printf("'%s' is :map's option. Please use -option style instead.", illegal))
    endif
endfunction "}}}

function! s:parse_rhs(q_args) "{{{
    return [a:q_args, '']
endfunction "}}}

function! s:parse_args(q_args) "{{{
    " NOTE: Currently :DefMap and :Map arguments are the same.

    let modes = ''
    let options = {}
    let lhs = ''
    let rhs = ''
    let create_instance = 'new'

    try
        let q_args = a:q_args
        let q_args = s:skip_spaces(q_args)

        " Allow no arguments `Map` to list all modes' mappings.
        if q_args == '' | throw create_instance | endif

        let [modes    , q_args] = s:parse_modes(q_args)
        let q_args = s:skip_spaces(q_args)
        " Allow no options and lhs `Map [n]` to list all modes' mappings.
        if q_args == '' | throw create_instance | endif

        let [options  , q_args] = s:parse_options(q_args)
        let options = s:add_pragmas(options)
        let q_args = s:skip_spaces(q_args)
        " Allow no lhs `Map [n]` to list all modes' mappings.
        if q_args == '' | throw create_instance | endif

        let [lhs, q_args] = s:parse_lhs(q_args)
        let q_args = s:skip_spaces(q_args)
        " Allow no rhs `Map [n] lhs` to list all modes' mappings.
        if q_args == '' | throw create_instance | endif

        let [rhs, q_args] = s:parse_rhs(q_args)

        " Assert q_args == ''
    catch /^new$/
        " Fall through.
    endtry
    return s:map_info_new(modes, options, lhs, rhs)
endfunction "}}}


" Mapping
function! emap#compile_map(map, mode, ...) "{{{
    let options = a:0 != 0 ? a:1 : s:add_pragmas({})

    " TODO Parse nested key notation.
    let keys = s:split_to_keys(a:map)

    if s:pragma_has(options, s:PRAGMA_IGNORE_SPACES)
        let whitespaces = '^[ \t]\+$'
        let keys = filter(keys, 'v:val !~# whitespaces')
    endif

    return join(map(keys, 's:eval_special_key(v:val, a:mode, options)'), '')
endfunction "}}}

function! s:split_to_keys(map)  "{{{
    " From arpeggio.vim
    "
    " Assumption: Special keys such as <C-u> are escaped with < and >, i.e.,
    "             a:lhs doesn't directly contain any escape sequences.
    return split(a:map, '\(<[^<>]\+>\|.\)\zs')
endfunction "}}}

function! s:eval_special_key(map, mode, options) "{{{
    if a:map =~# '^<[^<>]\+>$'
        let map_name = s:matchstr(a:map, '^<\zs[^<>]\+\ze>$')
        let named_map_rhs = s:named_map.maparg(s:get_snr_named_lhs(map_name), a:mode)
        let macro_map_rhs = s:macro_map.maparg(s:get_snr_macro_lhs(map_name), a:mode)

        " Assert map_name != ''

        " TODO Priority

        if a:map ==# '<SID>'
            return s:vimrc_snr_prefix()
        elseif macro_map_rhs != ''
            " Found :DefMacroMap's mapping. Return rhs definition.
            return macro_map_rhs
        elseif named_map_rhs != ''
            " Found :DefMap's mapping. Return <SNR> named mapping.
            return s:get_snr_named_lhs(map_name)
        else
            " Built-in key notation (:help key-notation)
            "
            " Some keys are not changed despite built-in key notation.
            " ("\<EOL>" == "<EOL>")
            "
            " - <EOL>
            " - <Nop>
            return a:map
        endif
    else
        " Other character like 'a', 'b', ...
        return a:map
    endif
endfunction "}}}

function! s:get_map_excmd(mode, options, lhs, rhs) "{{{
    let noremap = get(a:options, 'noremap', 0)
    return join([
    \   printf('%s%smap', a:mode, noremap ? 'nore' : ''),
    \   s:convert_options(a:options),
    \   a:lhs,
    \   a:rhs
    \])
endfunction "}}}

function! s:get_unmap_excmd(mode, options, lhs) "{{{
    return join([
    \   printf('%sunmap', a:mode),
    \   s:convert_options(a:options),
    \   a:lhs,
    \])
endfunction "}}}

function! s:get_macro_lhs(map) "{{{
    return '@' . a:map
endfunction "}}}

function! s:get_snr_macro_lhs(map) "{{{
    return s:EMAP_SNR . s:get_macro_lhs(a:map)
endfunction "}}}

function! s:get_named_lhs(map) "{{{
    return '$' . a:map
endfunction "}}}

function! s:get_snr_named_lhs(map) "{{{
    return s:EMAP_SNR . s:get_named_lhs(a:map)
endfunction "}}}

" Mapping info object to give to plugins.
" This will be created by `s:parse_args()`.
" s:map_info {{{
let s:map_info = {'modes': '', 'options': {}, 'lhs': '', 'rhs': ''}

function! s:map_info_new(modes, options, lhs, rhs) "{{{
    let obj = deepcopy(s:map_info)

    for varname in keys(a:)
        let obj[varname] = deepcopy(a:[varname])
    endfor

    return obj
endfunction "}}}

lockvar s:map_info
" }}}


" Set SID to convert "<SID>" to "<SNR>...".
function! emap#set_sid(sid) "{{{
    let sid = a:sid + 0
    if sid ==# 0
        call s:error(s:argument_error("Invalid SID."))
        return
    endif
    let s:vimrc_sid = sid
endfunction "}}}

function! emap#set_sid_from_sfile(sfile) "{{{
    let sid = s:get_sid_from_sfile(a:sfile)
    if sid == ''
        let msg = printf("emap#set_sid_from_sfile(): '%s' is not loaded yet.", a:sfile)
        call s:error(s:argument_error(msg))
        return
    endif
    call emap#set_sid(sid)
endfunction "}}}

function! s:get_sid_from_sfile(sfile) "{{{
    " From `s:snr_prefix()` of `autoload/textobj/user.vim`.

    redir => result
        silent scriptnames
    redir END

    for line in split(result, '\n')
        let _ = s:matchlist(line, '^\s*\(\d\+\):\s*\(.*\)$')
        if a:sfile ==# _[2]
            return _[1]
        endif
    endfor

    return ''
endfunction "}}}

function! s:vimrc_snr_prefix() "{{{
    if s:vimrc_sid ==# -1
        call s:error(
        \   "Your SID is not set.",
        \   "Please set by emap#set_sid()",
        \   "or emap#set_sid_from_sfile().",
        \)
        return ''
    endif
    return printf('<SNR>%d_', s:vimrc_sid)
endfunction "}}}


" Pragma
function! emap#available_pragmas() "{{{
    return keys(s:pragmas)
endfunction "}}}

function! emap#group_pragmas() "{{{
    return keys(s:GROUP_PRAGMAS)
endfunction "}}}

function! s:is_valid_pragmas(pragmas) "{{{
    return s:has_all_of(emap#available_pragmas(), a:pragmas)
endfunction "}}}

function! s:is_group_pragma(pragma) "{{{
    " NOTE: This receives one pragma, not List.
    return s:has_elem(emap#group_pragmas(), a:pragma)
endfunction "}}}

function! s:convert_pragmas(pragmas) "{{{
    " NOTE: This function ignores invalid pragmas.
    let pragmas = type(a:pragmas) == type([]) ? a:pragmas : [a:pragmas]
    let ret = []
    for p in pragmas
        if s:is_group_pragma(p)
            let ret += eval(s:GROUP_PRAGMAS[p])
        else
            let ret += [p]
        endif
    endfor
    return ret
endfunction "}}}

function! emap#set_pragmas(pragmas) "{{{
    let pragmas = s:convert_pragmas(a:pragmas)
    if !s:is_valid_pragmas(pragmas)
        call s:error(s:argument_error('emap#set_pragmas(): invalid pragmas'))
        return
    endif

    for i in pragmas
        let s:pragmas[i] = 1
    endfor
endfunction "}}}

function! emap#unset_pragmas(pragmas) "{{{
    let pragmas = s:convert_pragmas(a:pragmas)
    if !s:is_valid_pragmas(pragmas)
        call s:error(s:argument_error('emap#unset_pragmas(): invalid pragmas'))
        return
    endif

    for i in pragmas
        let s:pragmas[i] = 0
    endfor
endfunction "}}}

" }}}

" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
