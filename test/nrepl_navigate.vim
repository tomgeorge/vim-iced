let s:suite  = themis#suite('iced.nrepl.navigate')
let s:assert = themis#helper('assert')
let s:scope = themis#helper('scope')
let s:buf = themis#helper('iced_buffer')
let s:ch = themis#helper('iced_channel')
let s:sel = themis#helper('iced_selector')
let s:ex_cmd = themis#helper('iced_ex_cmd')
let s:qf = themis#helper('iced_quickfix')
let s:kondo = themis#helper('iced_clj_kondo')

let s:funcs = s:scope.funcs('autoload/iced/nrepl/navigate.vim')
let s:temp_file = tempname()

function! s:setup(opts) abort " {{{
  let g:iced_enable_clj_kondo_analysis = v:false
  let g:iced_cache_directory = ''

  call writefile([''], s:temp_file)
  call s:sel.mock()
  call s:ex_cmd.mock()
  call s:qf.mock()
  call iced#nrepl#change_current_session('clj')

  if has_key(a:opts, 'channel')
    call s:ch.mock({'status_value': 'open', 'relay': a:opts['channel']})
  endif

  if has_key(a:opts, 'buffer')
    call s:buf.start_dummy(a:opts['buffer'])
  endif
endfunction " }}}

function! s:teardown() abort " {{{
  call delete(s:temp_file)
  call iced#system#reset_component('clj_kondo')
  call s:buf.stop_dummy()
endfunction " }}}

function! s:suite.cycle_ns_test() abort
  call s:assert.equals(iced#nrepl#navigate#cycle_ns('foo.bar'), 'foo.bar-test')
  call s:assert.equals(iced#nrepl#navigate#cycle_ns('foo.bar-test'), 'foo.bar')
endfunction

let s:related_ns_test_ns_list = [
      \ 'foo.bar-test',
      \ 'foo.bar-spec',
      \ 'foo.bar.spec',
      \ 'foo.bar-dummy',
      \ 'foo.bar.baz',
      \ 'bar.baz',
      \ 'bar.baz-test',
      \ 'foo.baz.bar',
      \ ]

function! s:related_ns_relay(msg) abort
  if a:msg['op'] ==# 'iced-project-ns-list'
    return {'status': ['done'], 'project-ns-list': s:related_ns_test_ns_list}
  elseif a:msg['op'] ==# 'iced-pseudo-ns-path'
    return {'status': ['done'], 'path': s:temp_file}
  else
    return {'status': ['done']}
  endif
endfunction

function! s:suite.related_ns_test() abort
  call s:setup({
        \ 'channel': funcref('s:related_ns_relay'),
        \ 'buffer': ['(ns foo.bar)', '|'],
        \ })

  call iced#nrepl#navigate#related_ns()
  let config = s:sel.get_last_config()

  call s:assert.equals(sort(copy(config['candidates'])), [
        \ 'foo.bar-spec',
        \ 'foo.bar-test',
        \ 'foo.bar.spec',
        \ 'foo.baz.bar',
        \ ])

  call config['accept']('', 'foo.bar-test')
  call s:assert.equals(s:ex_cmd.get_last_args()['exe'], printf(':edit %s', s:temp_file))

  call s:teardown()
endfunction

function! s:jump_to_def_relay(info, msg) abort
  let resp = {'status': ['done']}
  if a:msg['op'] ==# 'info'
    call extend(resp, a:info)
  endif
  return resp
endfunction

function! s:suite.jump_to_def_test() abort
  let info = {
        \ 'file': '/path/to/file.clj',
        \ 'line': 1,
        \ 'column': 2,
        \ }
  call s:setup({'channel': {msg -> s:jump_to_def_relay(info, msg)}})

  call iced#nrepl#navigate#jump_to_def('dummy')
  call s:assert.equals(
        \ s:ex_cmd.get_last_args(),
        \ {'exe': ':edit /path/to/file.clj'})

  call s:teardown()
endfunction

function! s:suite.jump_to_def_in_jar_test() abort
  let info = {
        \ 'file': 'jar:file:/path/to/jarfile.jar!/path/to/file.clj',
        \ 'line': 1,
        \ 'column': 2,
        \ }
  call s:setup({'channel': {msg -> s:jump_to_def_relay(info, msg)}})

  call iced#nrepl#navigate#jump_to_def('dummy')
  call s:assert.equals(
        \ s:ex_cmd.get_last_args(),
        \ {'exe': ':edit zipfile:/path/to/jarfile.jar::path/to/file.clj'})

  call s:teardown()
endfunction

let s:test_test_vars = {
      \ 'baz-success-test': {'test': ''},
      \ 'baz-failure-test': {'test': ''},
      \ 'baz-test-fn': {}
      \ }

function! s:test_relay(msg) abort
  if a:msg['op'] ==# 'eval'
    return {'status': ['done'], 'value': '#''foo.bar/baz'}
  elseif a:msg['op'] ==# 'ns-vars-with-meta' && a:msg['ns'] ==# 'foo.bar-test'
    return {'status': ['done'], 'ns-vars-with-meta': s:test_test_vars}
  elseif a:msg['op'] ==# 'info'
    return {'status': ['done'], 'file': 'file:/path/to/file.clj', 'line': 1, 'column': 1}
  else
    return {'status': ['done']}
  endif
endfunction

function! s:suite.test_test() abort
  call s:setup({
        \ 'channel': funcref('s:test_relay'),
        \ 'buffer': ['(ns foo.bar)', '(defn baz [] "dummy"|)'],
        \ })

  let p = iced#nrepl#navigate#test()
  call iced#promise#wait(p)

  let config = s:sel.get_last_config()
  call s:assert.equals(sort(copy(config['candidates'])), [
        \ 'foo.bar-test/baz-failure-test',
        \ 'foo.bar-test/baz-success-test'])

  call config['accept']('', 'foo.bar-test/baz-success-test')
  call s:assert.equals(s:ex_cmd.get_last_args()['exe'], ':edit /path/to/file.clj')

  call s:teardown()
endfunction

function! s:browse_var_references_relay(msg) abort
  let op = a:msg['op']
  if op ==# 'info'
    return {'status': ['done'], 'ns': 'foo', 'name': 'bar'}
  elseif op ==# 'fn-refs'
    return {'status': ['done'], 'fn-refs': [
          \ {'file': s:temp_file, 'name': 'hello', 'doc': 'doc hello', 'line': 12},
          \ {'file': 'non_existing.txt', 'name': 'world', 'doc': 'doc world', 'line': 34},
          \ ]}
  elseif op ==# 'eval'
    return {'status': ['done'], 'value': 'foo.core'}
  else
    return {'status': ['done']}
  endif
endfunction

function! s:suite.browse_var_references_test() abort
  call s:setup({'channel': funcref('s:browse_var_references_relay')})

  call iced#nrepl#navigate#browse_var_references('foo/bar')
  let qf_list = s:qf.get_last_args()['list']
  call s:assert.equals(qf_list, [
        \ {'filename': s:temp_file, 'lnum': 12, 'text': 'hello: doc hello'},
        \ ])

  call s:teardown()
endfunction

function! s:browse_var_dependencies_relay(msg) abort
  let op = a:msg['op']
  if op ==# 'info'
    return {'status': ['done'], 'ns': 'foo', 'name': 'bar'}
  elseif op ==# 'fn-deps'
    return {'status': ['done'], 'fn-deps': [
          \ {'file': s:temp_file, 'name': 'world', 'doc': 'doc world', 'line': 56},
          \ {'file': 'non_existing.txt', 'name': 'neko', 'doc': 'doc neko', 'line': 78},
          \ ]}
  elseif op ==# 'eval'
    return {'status': ['done'], 'value': 'foo.core'}
  else
    return {'status': ['done']}
  endif
endfunction

function! s:suite.browse_var_dependencies_test() abort
  call s:setup({'channel': funcref('s:browse_var_dependencies_relay')})

  call iced#nrepl#navigate#browse_var_dependencies('foo/bar')
  let qf_list = s:qf.get_last_args()['list']
  call s:assert.equals(qf_list, [
        \ {'filename': s:temp_file, 'lnum': 56, 'text': 'world: doc world'}
        \ ])

  call s:teardown()
endfunction

function! s:__browse_references_reply(msg) abort
  let op = a:msg['op']
  if op ==# 'eval'
    return {'status': ['done'], 'value': '#''example/var'}
  elseif op ==# 'fn-refs'
    return {'status': ['done'], 'fn-refs': [
          \ {'file': s:temp_file, 'name': 'nrepl hello', 'doc': 'doc nrepl hello', 'line': 12},
          \ {'file': 'non_existing.txt', 'name': 'world', 'doc': 'doc world', 'line': 34},
          \ ]}
  else
    return {'status': ['done']}
  endif
endfunction

function! s:suite.browse_references_nrepl_test() abort
  call s:setup({
        \ 'channel': funcref('s:__browse_references_reply'),
        \ 'buffer': ['(dummy|)'],
        \ })
  let g:iced_cache_directory = ''
  let g:iced_enable_clj_kondo_analysis = v:false

  call iced#nrepl#navigate#browse_references()
  let qf_list = s:qf.get_last_args()['list']
  call s:assert.equals(qf_list, [
        \ {'lnum': 12, 'filename': s:temp_file, 'text': 'nrepl hello: doc nrepl hello'},
        \ ])

  call s:teardown()
endfunction

function! s:suite.browse_references_clj_kondo_test() abort
  call s:setup({
        \ 'channel': {_ -> {'status': ['done'], 'value': '#''X/v'}},
        \ 'buffer': ['(dummy|)'],
        \ })
  let g:iced_enable_clj_kondo_analysis = v:true
  call s:kondo.mock({'var-usages': [
        \ {'from': 'A', 'from-var': 'a', 'to': 'X', 'name': 'v', 'filename': s:temp_file, 'row': 1},
        \ {'from': 'B', 'from-var': 'b', 'to': 'X', 'name': 'v', 'filename': s:temp_file, 'row': 2},
        \ {'from': 'D', 'from-var': 'd', 'to': 'X', 'name': 'v', 'filename': 'non_existing_file', 'row': 3},
        \ {'from': 'C', 'from-var': 'c', 'to': 'X', 'name': 'different_var', 'filename': s:temp_file, 'row': 4},
        \ {'from': 'E', 'from-var': 'e', 'to': 'Y', 'name': 'another ns', 'filename': s:temp_file, 'row': 5},
        \ ]})

  call iced#nrepl#navigate#browse_references()

  let qf_list = s:qf.get_last_args()['list']
  call s:assert.equals(qf_list, [
        \ {'lnum': 1, 'filename': s:temp_file, 'text': 'A/a'},
        \ {'lnum': 2, 'filename': s:temp_file, 'text': 'B/b'},
        \ ])

  call s:teardown()
endfunction

function! s:__browse_dependencies_reply(msg) abort
  let op = a:msg['op']
  if op ==# 'eval'
    return {'status': ['done'], 'value': '#''example/var'}
  elseif op ==# 'fn-deps'
    return {'status': ['done'], 'fn-deps': [
          \ {'file': s:temp_file, 'name': 'nrepl hello', 'doc': 'doc nrepl hello', 'line': 12},
          \ {'file': 'non_existing.txt', 'name': 'world', 'doc': 'doc world', 'line': 34},
          \ ]}
  else
    return {'status': ['done']}
  endif
endfunction

function! s:suite.browse_dependencies_nrepl_test() abort
  call s:setup({
        \ 'channel': funcref('s:__browse_dependencies_reply'),
        \ 'buffer': ['(dummy|)'],
        \ })
  let g:iced_cache_directory = ''
  let g:iced_enable_clj_kondo_analysis = v:false

  call iced#nrepl#navigate#browse_dependencies()
  let qf_list = s:qf.get_last_args()['list']
  call s:assert.equals(qf_list, [
        \ {'lnum': 12, 'filename': s:temp_file, 'text': 'nrepl hello: doc nrepl hello'},
        \ ])

  call s:teardown()
endfunction

function! s:suite.browse_dependencies_clj_kondo_test() abort
  call s:setup({
        \ 'channel': {_ -> {'status': ['done'], 'value': '#''A/a'}},
        \ 'buffer': ['(dummy|)'],
        \ })
  let g:iced_enable_clj_kondo_analysis = v:true
  call s:kondo.mock({
        \ 'var-usages': [
        \   {'from': 'A', 'from-var': 'a', 'to': 'X', 'name': 'v'},
        \   {'from': 'A', 'from-var': 'a', 'to': 'X', 'name': 'w'},
        \   {'from': 'A', 'from-var': 'a', 'to': 'clojure.core', 'name': 'str'},
        \   {'from': 'A', 'from-var': 'different_var', 'to': 'X', 'name': 'v'},
        \   {'from': 'another ns', 'from-var': 'a', 'to': 'X', 'name': 'v'},
        \ ],
        \ 'var-definitions': [
        \   {'ns': 'X' , 'name': 'v', 'filename': s:temp_file, 'row': 1},
        \   {'ns': 'X' , 'name': 'w', 'filename': s:temp_file, 'row': 2},
        \   {'ns': 'clojure.core' , 'name': 'str', 'filename': s:temp_file, 'row': 9},
        \ ],
        \ })

  call iced#nrepl#navigate#browse_dependencies()

  let qf_list = s:qf.get_last_args()['list']
  call s:assert.equals(qf_list, [
        \ {'lnum': 1, 'filename': s:temp_file, 'text': 'X/v'},
        \ {'lnum': 2, 'filename': s:temp_file, 'text': 'X/w'},
       \ ])

  call s:teardown()
endfunction
