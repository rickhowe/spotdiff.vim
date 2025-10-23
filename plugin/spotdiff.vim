" spotdiff.vim : A range and area selectable diffthis to compare partially
"
" Last Change: 2025/10/23
" Version:     6.0
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2014-2025 by Rick Howe
" License:     MIT

if exists('g:loaded_spotdiff') || !has('diff') ||
                                      \(v:version < 900 && !has('nvim-0.7.0'))
  finish
endif
let g:loaded_spotdiff = 6.0

let s:save_cpo = &cpoptions
set cpo&vim

command! -range -bar Diffthis call spotdiff#Diffthis(<line1>, <line2>)
command! -bang -bar Diffoff call spotdiff#Diffoff(<bang>0)
command! -bar Diffupdate call spotdiff#Diffupdate()

command! -range -bang -bar
                \ VDiffthis call spotdiff#VDiffthis(<line1>, <line2>, <bang>0)
command! -bang -bar VDiffoff call spotdiff#VDiffoff(<bang>0)
command! -bar VDiffupdate call spotdiff#VDiffupdate()

for [s:mod, s:key, s:plg, s:cmd] in [
        \['v', 't', 'VDiffthis', '#VDiffthis(line("''<"), line("''>"), 0)'],
        \['v', 'T', 'VDiffthis!', '#VDiffthis(line("''<"), line("''>"), 1)'],
        \['n', 'o', 'VDiffoff', '#VDiffoff(0)'],
        \['n', 'O', 'VDiffoff!', '#VDiffoff(1)'],
        \['n', 'u', 'VDiffupdate', '#VDiffupdate()'],
        \['n', 't', 'VDiffthis', 'VDiffOpFunc0'],
        \['n', 'T', 'VDiffthis!', 'VDiffOpFunc1']]
  let s:key = '<Leader>' . s:key
  let s:plg = '<Plug>(' . s:plg . ')'
  let s:cmd = (s:cmd[0] == '#') ? ':<C-U>call spotdiff' . s:cmd . '<CR>' :
                    \':<C-U>let &operatorfunc = ''<SID>' . s:cmd . '''<CR>g@'
  if !hasmapto(s:plg, s:mod) && empty(maparg(s:key, s:mod))
    if get(g:, 'VDiffDoMapping', 1)
      call execute(s:mod . 'map <silent> ' . s:key . ' ' . s:plg)
    endif
  endif
  call execute(s:mod . 'noremap <silent> ' . s:plg . ' ' . s:cmd)
endfor

function! s:VDiffOpFunc0(vm) abort
  call spotdiff#VDiffOpFunc(a:vm, 0)
endfunction

function! s:VDiffOpFunc1(vm) abort
  call spotdiff#VDiffOpFunc(a:vm, 1)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
