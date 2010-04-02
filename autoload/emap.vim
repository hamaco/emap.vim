" vim:foldmethod=marker:fen:
scriptencoding utf-8
" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}

" TODO
" - Nested <...> expression.
" - To be hackable.

" Script variables {{{
let s:vimrc_sid = -1
" }}}

" Functions {{{

" Utilities
function! s:each_char(str) "{{{
    return split(a:str, '\zs')
endfunction "}}}

function! s:skip_spaces(q_args) "{{{
    return substitute(a:q_args, '^\s*', '', '')
endfunction "}}}

function! s:parse_error(msg) "{{{
    return 'parse error: ' . a:msg
endfunction "}}}


" For ex commands
function! emap#load() "{{{
    " TODO autoload function for :DefMap, :Map.
    command!
    \   -nargs=+
    \   DefMap
    \   execute s:cmd_defmap(<q-args>)

    command!
    \   -nargs=+
    \   Map
    \   execute s:cmd_map(<q-args>)
endfunction "}}}

function! s:cmd_defmap(q_args) "{{{
    Assert len(a:q_args) >= 3

    try
        let [modes, options, lhs, rhs] = s:parse_args(a:q_args)
    catch /^parse error:/
        ShowStackTrace
        return
    endtry

    let ret = []
    for m in s:each_char(modes)
        call add(ret,
        \   s:get_map_excmd(m, options, s:sid_named_map(lhs), s:convert_map(rhs, m)))
    endfor

    " Decho ':DefMap'
    " VarDump ret

    " Let :execute at the caller scope.
    return join(ret, '|')
endfunction "}}}

function! s:cmd_map(q_args) "{{{
    try
        let [modes, options, lhs, rhs] = s:parse_args(a:q_args)
    catch /^parse error:/
        ShowStackTrace
        return
    endtry

    let ret = []
    for m in s:each_char(modes)
        call add(ret,
        \   s:get_map_excmd(m, options, s:convert_map(lhs, m), s:convert_map(rhs, m)))
    endfor

    " Decho ':Map'
    " VarDump ret

    " Let :execute at the caller scope.
    return join(ret, '|')
endfunction "}}}

function! s:convert_options(options) "{{{
    let expr = get(a:options, 'expr', 0) ? '<expr>' : ''
    return expr
endfunction "}}}

function! s:convert_map(lhs, ...) "{{{
    " TODO Parse nested key notation.
    return join(map(s:split_to_keys(a:lhs), 'call("s:eval_special_key", [v:val] + a:000)'), '')
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

function! s:split_to_keys(map)  "{{{
    " From arpeggio.vim
    "
    " Assumption: Special keys such as <C-u> are escaped with < and >, i.e.,
    "             a:lhs doesn't directly contain any escape sequences.
    return split(a:map, '\(<[^<>]\+>\|.\)\zs')
endfunction "}}}

function! s:eval_special_key(map, ...) "{{{
    if a:map =~# '^<[^<>]\+>$'
        let evaled = eval(printf('"\%s"', a:map))
        let named_map =
        \   matchstr(a:map, '^<\zs[^<>]\+\ze>$')
        let exists_named_map =
        \   call('maparg', [s:sid_named_map(named_map)] + a:000) != ''

        Assert named_map != ''

        if a:map ==# '<SID>'
            return s:snr_prefix()
        elseif evaled !=# a:map
            " Built-in key notation (:help key-notation)
            " XXX: <EOL> is not changed?
            " ("\<EOL>" == "<EOL>")
            return evaled
        elseif exists_named_map
            " Found named mapping.
            return s:sid_named_map(named_map)
        else
            return a:map
        endif
    else
        return a:map
    endif
endfunction "}}}

function! s:sid_named_map(map) "{{{
    " All named mappings are mapped after '<SID>@'.
    return '<SID>@' . a:map
endfunction "}}}


" Parser for ex commands.
function! s:get_modes(q_args) "{{{
    let [arg, rest] = s:get_one_arg_from_q_args(a:q_args)
    let modes = matchstr(arg, '^\[\zs[nvoiclxs]\+\ze\]')
    Assert modes != ''
    return [modes, rest]
endfunction "}}}

function! s:get_options(q_args) "{{{
    let q_args = a:q_args
    let opt = {}

    while !empty(q_args)
        let [a, rest] = s:get_one_arg_from_q_args(q_args)
        if a[0] !=# '-'
            break
        endif
        let q_args = rest

        if a ==# '--'
            break
        elseif a[0] ==# '-'
            if a[1:] ==# 'expr'
                let opt.expr = 1
            elseif a[1:] ==# 'noremap'
                let opt.noremap = 1
            else
                throw s:parse_error(printf("unknown option '%s'.", a))
            endif
        endif
    endwhile

    return [opt, q_args]
endfunction "}}}

function! s:get_one_arg_from_q_args(q_args) "{{{
    let arg = s:skip_spaces(a:q_args)
    let head = matchstr(arg, '^.\{-}[^\\]\ze\([ \t]\|$\)')
    let rest = strpart(arg, strlen(head))
    return [head, rest]
endfunction "}}}

function! s:parse_args(q_args) "{{{
    " NOTE: Currently :DefMap and :Map arguments are the same.

    let q_args = a:q_args

    let q_args = s:skip_spaces(q_args)
    let [modes    , q_args] = s:get_modes(q_args)

    let q_args = s:skip_spaces(q_args)
    let [options  , q_args] = s:get_options(q_args)

    let q_args = s:skip_spaces(q_args)
    let [lhs, q_args] = s:get_one_arg_from_q_args(q_args)

    let q_args = s:skip_spaces(q_args)
    let rhs = q_args

    Assert lhs != ''
    Assert rhs != ''

    return [modes, options, lhs, rhs]
endfunction "}}}


" Set SID to convert "<SID>" to "<SNR>...".
function! emap#set_sid(sid) "{{{
    let s:vimrc_sid = a:sid + 0
endfunction "}}}

function! emap#set_sid_from_sfile(sfile) "{{{
    let sid = s:get_sid_from_sfile(a:sfile)
    if sid != ''
        call emap#set_sid(sid)
    endif
endfunction "}}}

function! s:get_sid_from_sfile(sfile) "{{{
    " From `s:snr_prefix()` of `autoload/textobj/user.vim`.

    redir => result
        silent scriptnames
    redir END

    for line in split(result, '\n')
        let _ = matchlist(line, '^\s*\(\d\+\):\s*\(.*\)$')
        if a:sfile ==# _[2]
            return _[1]
        endif
    endfor

    return ''
endfunction "}}}

function! s:snr_prefix() "{{{
    if s:vimrc_sid ==# -1
        echoerr "Your SID is not set."
        \       "Please set by emap#set_sid()"
        \       "or emap#set_sid_from_sfile()."
        return ''
    endif
    return printf('<SNR>%d_', s:vimrc_sid)
endfunction "}}}
" }}}

" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}