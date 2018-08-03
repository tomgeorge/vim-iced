scriptencoding utf-8
let s:save_cpo = &cpo
set cpo&vim

let s:V  = vital#of('iced')
let s:S  = s:V.import('Data.String')
let s:B  = s:V.import('Vim.Buffer')
let s:BM = s:V.import('Vim.BufferManager')

let g:iced#buffer#name = get(g:, 'iced#buffer#name', 'nrepl')
let g:iced#buffer#max_line = get(g:, 'iced#buffer#max_line', 512)

let s:manager = v:none
let s:info = {}

function! s:focus_window(bufwin_num) abort
  execute a:bufwin_num . 'wincmd w'
endfunction

function! s:repl_bufwinnr() abort
  return bufwinnr(get(s:info, 'bufnr', -1))
endfunction

function! s:apply_buffer_settings() abort
  let n = get(s:info, 'bufnr', -1)
  if n < 0
    return
  endif

  call setbufvar(n, '&buflisted', 0)
  call setbufvar(n, '&buftype', 'nofile')
  call setbufvar(n, '&filetype', 'clojure')
  call setbufvar(n, '&modifiable', 0)
  call setbufvar(n, '&swapfile', 0)
endfunction

function! iced#buffer#is_initialized() abort
  return (empty(s:info) ? v:false : v:true)
endfunction

function! iced#buffer#init() abort
  if iced#buffer#is_initialized()
    return
  endif

  let s:manager = s:BM.new()
  let s:info = s:manager.open(g:iced#buffer#name)

  call s:apply_buffer_settings()
  silent execute ':q'
endfunction

function! s:is_visible() abort
  return (s:repl_bufwinnr() != -1)
endfunction

function! iced#buffer#open() abort
  let n = get(s:info, 'bufnr', -1)
  if n < 0
    return
  endif

  if s:is_visible()
    call s:focus_window(s:repl_bufwinnr())
  else
    call s:B.open(n, {'opener': 'split'})
    call iced#buffer#append(';; Iced Buffer')
  endif
endfunction

function! s:delete_color_code(s) abort
  return substitute(a:s, '\[[0-9;]*m', '', 'g')
endfunction

function! iced#buffer#append(s) abort
  let n = get(s:info, 'bufnr', -1)
  if n < 0
    return
  endif

  call setbufvar(n, '&modifiable', 1)
  for line in split(a:s, '\r\?\n')
    let line = s:delete_color_code(line)
    call appendbufline(n, '$', line)
  endfor
  call setbufvar(n, '&modifiable', 0)

  " scroll to bottom
  if s:is_visible()
    let current_window = bufwinnr(bufnr('%'))
    call s:focus_window(s:repl_bufwinnr())
    silent normal! G
    call s:focus_window(current_window)
  endif
endfunction

function! iced#buffer#clear() abort
  let visibled = s:is_visible()
  let current_window = bufwinnr(bufnr('%'))

  call iced#buffer#open()

  setlocal modifiable
  silent normal! ggdG
  setlocal nomodifiable

  if visibled
    call s:focus_window(current_window)
  else
    silent execute ':q'
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo