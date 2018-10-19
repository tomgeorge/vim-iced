let s:suite  = themis#suite('iced.nrepl.spec')
let s:assert = themis#helper('assert')
let s:scope = themis#helper('scope')
let s:funcs = s:scope.funcs('autoload/iced/nrepl/spec.vim')

let s:cat_sample = [
      \ 'clojure.spec.alpha/cat',
      \   ':bindings',
      \     ':clojure.core.specs.alpha/bindings',
      \   ':body',
      \     ['clojure.spec.alpha/*', 'clojure.core/any?'],
      \ ]

let s:cat_once_sample = [
      \ 'clojure.spec.alpha/cat', ':foo', '::bar']

function! s:suite.format_cat_test() abort
  call s:assert.equals(iced#nrepl#spec#format(s:cat_sample),
        \ join([
        \   '(s/cat',
        \   '  :bindings :clojure.core.specs.alpha/bindings',
        \   '  :body (s/* any?))',
        \ ], "\n"))

  call s:assert.equals(iced#nrepl#spec#format(s:cat_once_sample),
        \ '(s/cat :foo ::bar)')
endfunction

let s:or_sample = [
      \ 'clojure.spec.alpha/cat',
      \   ':foo',
      \     ['clojure.spec.alpha/or',
      \       ':string', 'clojure.core/string?',
      \       ':none', 'clojure.core/nil?',
      \     ],
      \ ]

function! s:suite.format_or_test() abort
  call s:assert.equals(iced#nrepl#spec#format(s:or_sample),
        \ join([
        \   '(s/cat',
        \   '  :foo (s/or',
        \   '         :string string?',
        \   '         :none nil?))',
        \ ], "\n"))
endfunction

let s:keys_sample = [
      \ 'clojure.spec.alpha/keys',
      \   ':req-un', ['::foo.core/bar', '::bar.core/baz'],
      \   ':opt-un', ['::baz.core/foo'],
      \ ]

let s:keys_once_sample = [
      \ 'clojure.spec.alpha/keys',
      \   ':req-un', ['::foo.core/bar'],
      \ ]

function! s:suite.format_keys_test() abort
  call s:assert.equals(iced#nrepl#spec#format(s:keys_sample),
        \ join([
        \   '(s/keys',
        \   '  :req-un [::foo.core/bar ::bar.core/baz]',
        \   '  :opt-un [::baz.core/foo])',
        \ ], "\n"))

  call s:assert.equals(iced#nrepl#spec#format(s:keys_once_sample),
        \ '(s/keys :req-un [::foo.core/bar])')
endfunction

let s:fspec_sample = [
      \ 'clojure.spec.alpha/fspec',
      \   ':args', [
      \     'clojure.spec.alpha/cat',
      \       ':foo',
      \         ['clojure.spec.alpha/or', ':str', 'string?', ':none', 'nil?'],
      \   ],
      \   ':ret', 'any?'
      \ ]

function! s:suite.format_fspec_test() abort
  call s:assert.equals(iced#nrepl#spec#format(s:fspec_sample),
        \ join([
        \   '(s/fspec',
        \   '  :args (s/cat',
        \   '          :foo (s/or',
        \   '                 :str string?',
        \   '                 :none nil?))',
        \   '  :ret any?)',
        \ ], "\n"))
endfunction
